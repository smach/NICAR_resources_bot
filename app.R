library(shiny)
library(shinychat)
library(ellmer)
library(ragnar)
library(reactable)
library(htmlwidgets)
library(bslib)
library(dplyr)
library(htmltools)
library(promises)
library(arrow)
library(DBI)
source("helpers_ui.R")
source("helpers_server.R")
source("helpers_logging.R")

# Load environment variables
if (file.exists(".Renviron")) {
  readRenviron(".Renviron")
}

ui <- page_fillable(
  theme = custom_theme,

  tags$head(
    tags$style(custom_style)
  ),

  # Title panel
  div(class = "header-section", header_content),

  layout_sidebar(
    sidebar = sidebar(
      width = "33%",
      open = "open",
      title = div(
        "NICAR Resources Assistant",
        style = "color: #1B3A4B; font-weight: 600;"
      ),
      class = "chat-sidebar",

      # Sample questions
      div(
        style = "margin-bottom: 8px;",
        h5(
          "Try these questions:",
          style = "margin: 0 0 6px 0; font-size: 14px; color: #1B3A4B; font-weight: 600;"
        ),
        actionButton(
          "ask_mapping",
          "What resources are about mapping or GIS?",
          class = "btn-sample-questions"
        ),
        actionButton(
          "ask_genai",
          "Show me generative AI resources from 2026",
          class = "btn-sample-questions"
        ),
        actionButton(
          "ask_scraping",
          "What web scraping tutorials are available?",
          class = "btn-sample-questions"
        )
      ),

      # Filter button container
      div(
        id = "show_in_table_container",
        style = "margin-bottom: 15px;",
        uiOutput("show_in_table_button")
      ),

      chat_ui(
        "resource_chat",
        messages = list(
          list(
            role = "assistant",
            content = chatbot_welcome
          )
        ),
        placeholder = "Ask about NICAR resources...",
        height = "calc(100vh - 350px)"
      )
    ),

    # Main panel with resource table
    div(
      style = "padding: 20px; background-color: white;",
      div(
        style = "margin-bottom: 20px;",
        fluidRow(
          column(
            8,
            h3(
              "Resource Directory",
              style = "margin: 0; color: #1B3A4B; font-weight: 600;"
            ),
            p(
              "Click any resource title to visit it \u2022 Click row expander for details \u2022 Search filters all columns",
              style = "margin: 5px 0 0 0; color: #666; font-size: 14px;"
            )
          ),
          column(
            4,
            div(
              class = "stats-box",
              style = "text-align: center;",
              textOutput("table_stats")
            )
          )
        )
      ),
      reactableOutput("resource_table", height = "calc(100vh - 330px)")
    )
  ),

  # Footer
  tags$footer(
    style = "
      position: fixed;
      bottom: 2px;
      right: 12px;
      font-size: 11px;
      color: #999;
      background: white;
      padding: 4px 8px;
      border-radius: 3px;
    ",
    HTML(
      "App by <a href='https://machlis.com' target='_blank' style='color: #888;'>Sharon Machlis</a> & Claude AI"
    )
  )
)

server <- function(input, output, session) {
  # Load resource data
  resources_data <- reactive({
    tryCatch(
      {
        read_parquet("resources_for_app.parquet")
      },
      error = function(e) {
        data.frame(
          Year = integer(),
          What = character(),
          Who = character(),
          URL = character(),
          Tags = character(),
          Type = character(),
          AdditionalComments = character()
        )
      }
    )
  })

  # Initialize store connection
  store <- NULL

  tryCatch(
    {
      store <- ragnar_store_connect(
        "nicar_resources.duckdb",
        read_only = TRUE
      )
      dbExecute(store@con, "LOAD fts;")
    },
    error = function(e) {
      message("Could not connect to ragnar store: ", e$message)
    }
  )

  # ==== SEARCH TOOLS ====

  # Tool 1: Topic-based semantic search with optional metadata filters
  search_resources <- function(
    query,
    year = NULL,
    type = NULL,
    tags = NULL,
    top_k = 20
  ) {
    filter_components <- list()

    if (!is.null(year)) {
      year_int <- as.integer(year)
      filter_components$year <- rlang::expr(Year == !!year_int)
    }

    if (!is.null(type)) {
      filter_components$type <- rlang::expr(Type == !!type)
    }

    # Combine filters with AND logic (tags handled as post-filter below)
    if (length(filter_components) == 0) {
      filter_expr <- NULL
    } else if (length(filter_components) == 1) {
      filter_expr <- filter_components[[1]]
    } else {
      filter_expr <- Reduce(
        function(x, y) rlang::expr(!!x & !!y),
        filter_components
      )
    }

    # Retrieve more results if we need to post-filter by tags
    retrieve_k <- if (!is.null(tags)) top_k * 3 else top_k

    results <- ragnar_retrieve_vss(
      store,
      query,
      top_k = retrieve_k,
      filter = !!filter_expr
    )

    # Post-filter by tag (substring match in R, since DuckDB LIKE not
    # available through ragnar's rlang filter interface)
    if (!is.null(tags)) {
      tag_lower <- tolower(tags)
      results <- results |>
        filter(grepl(tag_lower, Tags, fixed = TRUE)) |>
        head(top_k)
    }

    results |>
      select(What, Who, Year, Tags, Type, AdditionalComments, URL)
  }

  # Tool 2: Search by contributor name
  search_by_contributor <- function(contributor_name, top_k = 10) {
    ragnar_retrieve_bm25(
      store,
      contributor_name,
      top_k = top_k * 2,
      conjunctive = FALSE
    ) |>
      filter(grepl(contributor_name, Who, ignore.case = TRUE)) |>
      head(top_k) |>
      select(What, Who, Year, Tags, Type, AdditionalComments, URL)
  }

  # Tool 3: Highlight resources for table filtering
  highlight_resources <- function(titles) {
    if (length(titles) > 0) {
      clean_titles <- unlist(titles)
      ai_resource_titles(clean_titles)
      return(paste(
        "Table ready to filter to",
        length(clean_titles),
        "resources."
      ))
    } else {
      ai_resource_titles(NULL)
      return("No resources to highlight.")
    }
  }

  # ==== STATE MANAGEMENT ====
  chat_obj <- reactiveVal(NULL)
  ai_resource_titles <- reactiveVal(NULL)
  table_filter <- reactiveVal(NULL)
  user_api_key <- reactiveVal(NULL)
  key_source <- reactiveVal("app_key")

  # Show API key modal on startup if no key in environment
  observe({
    env_key <- Sys.getenv("GEMINI_API_KEY")
    if (env_key == "" && is.null(user_api_key())) {
      showModal(modalDialog(
        title = "Gemini API Key Required",
        p(
          "This app uses Google's Gemini 2.5 Flash to answer questions about NICAR resources."
        ),
        p(
          "Please enter your Google Gemini API key to use the chat feature. There is a free tier."
        ),
        p(tags$a(
          "Get an API key in Google's AI Studio",
          href = "https://aistudio.google.com/api-keys",
          target = "_blank"
        )),
        textInput(
          "api_key_input",
          "Your Google API Key:",
          placeholder = "..."
        ),
        p(tags$small(
          "Your key is only used for this session and is not stored.",
          style = "color: #666;"
        )),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("submit_api_key", "Submit", class = "btn-primary")
        ),
        easyClose = FALSE
      ))
    }
  }) |>
    bindEvent(TRUE, once = TRUE)

  observeEvent(input$submit_api_key, {
    key <- input$api_key_input
    if (nchar(key) > 20) {
      user_api_key(key)
      key_source("user_key")
      removeModal()
    } else {
      showNotification("Please enter a valid key", type = "error")
    }
  })

  active_api_key <- reactive({
    env_key <- Sys.getenv("GEMINI_API_KEY")
    if (env_key != "") {
      return(env_key)
    }
    user_api_key()
  })

  # Initialize chat when API key is available
  observe({
    api_key <- active_api_key()
    if (is.null(api_key) || api_key == "" || is.null(store)) {
      return()
    }

    Sys.setenv(GEMINI_API_KEY = api_key)

    tryCatch(
      {
        # Tool 1: Resource search
        resource_search_tool <- tool(
          search_resources,
          name = "search_resources",
          description = "Search for NICAR conference resources by topic with optional filtering by year, type, and tags. Use this for topic-based queries like 'mapping resources', 'Python tutorials', 'AI tools'.",
          arguments = list(
            query = type_string(
              "The search query describing what kind of resources you're looking for (e.g., 'web scraping', 'data visualization', 'census data')"
            ),
            year = type_enum(
              values = c("2024", "2025", "2026"),
              description = "Filter by NICAR conference year. ONLY use when user explicitly mentions a year.",
              required = FALSE
            ),
            type = type_enum(
              values = c(
                "Presentation, Workshop, Repo or Tip Sheet",
                "Tool, Software or Resource",
                "Work Samples",
                "Unspecified"
              ),
              description = "Filter by resource type.",
              required = FALSE
            ),
            tags = type_string(
              "Filter by tag (e.g., '#python', '#genai', '#maps'). Tags are lowercase. Use a single tag for filtering; the search will find resources containing that tag among their multiple tags.",
              required = FALSE
            ),
            top_k = type_integer(
              "Number of resources to retrieve (default: 20)",
              required = FALSE
            )
          )
        )

        # System prompt
        system_prompt <- paste0(
          "You are a helpful assistant for finding NICAR conference resources from 2024-2026. ",
          "Today's date is ",
          format(Sys.Date(), "%B %d, %Y"),
          ". The current year is ",
          format(Sys.Date(), "%Y"),
          ". ",
          "Answer ONLY using information from the resource database - never use prior knowledge. \n\n",

          "TOOL SELECTION:\n",
          "- Topic queries (e.g., 'mapping', 'Python', 'AI tools'): use search_resources\n",
          "- Contributor queries (e.g., 'Ben Welsh', 'IRE'): use search_by_contributor\n",
          "- You can combine: first search by topic, then filter by year or tags if specified\n\n",

          "YEAR FILTERING (IMPORTANT):\n",
          "When the user mentions a specific year OR relative time like 'this year', 'last year', 'recent', 'latest', you MUST pass the year parameter to search_resources. ",
          "Translate relative references: 'this year' = ",
          format(Sys.Date(), "%Y"),
          ", 'last year' = ",
          as.integer(format(Sys.Date(), "%Y")) - 1L,
          ". ",
          "Do NOT rely on semantic search alone for year filtering - always use the year parameter.\n\n",

          "TAG FILTERING:\n",
          "Tags are stored lowercase with # prefix. When filtering by tag, use lowercase (e.g., '#python', '#genai', '#gis').\n",
          "Resources can have multiple tags. The filter matches any resource containing the specified tag.\n\n",

          "RESPONSE FORMAT:\n",
          "For each resource, include:\n",
          "- Title as a clickable markdown link: [Title](URL)\n",
          "- Contributors and year\n",
          "- Brief description from Additional Comments if available (1-2 sentences max)\n",
          "End each line with TWO SPACES for single line breaks.\n\n",

          "Example:\n\n",
          "**[First PMTiles Map](https://palewi.re/docs/first-pmtiles-map/)**  \n",
          "Ben Welsh (2026)  \n",
          "Learn how to display a massive dataset on an interactive map using PMTiles and MapLibre.\n\n",

          "After listing resources, call highlight_resources with the exact titles (not URLs). ",
          "IMPORTANT: After calling highlight_resources, do NOT repeat or summarize the resources you already listed. The tool call should be the last thing you do.\n\n",
          "If no resources match, say so briefly."
        )

        chat <- chat_google_gemini(
          system_prompt = system_prompt,
          model = "gemini-2.5-flash",
          echo = "none"
        )

        # Register tools
        chat$register_tool(resource_search_tool)

        contributor_search_tool <- tool(
          search_by_contributor,
          name = "search_by_contributor",
          description = "Search for resources by contributor name. Use this when the user asks about a specific person (e.g., 'resources by Simon Willison', 'what did Ben Welsh share').",
          arguments = list(
            contributor_name = type_string(
              "The contributor name or partial name to search for"
            ),
            top_k = type_integer(
              "Number of resources to retrieve (default: 10)",
              required = FALSE
            )
          )
        )
        chat$register_tool(contributor_search_tool)

        highlight_resources_tool <- tool(
          highlight_resources,
          name = "highlight_resources",
          description = "Update the resource table to show only specific resources. Call this AFTER search_resources or search_by_contributor with the exact titles of resources you are recommending. This enables a 'Show in Table' button.",
          arguments = list(
            titles = type_array(
              items = type_string(),
              description = "List of exact resource titles to highlight in the table"
            )
          )
        )
        chat$register_tool(highlight_resources_tool)

        chat_obj(chat)
        message("Chat initialized successfully")
      },
      error = function(e) {
        message("Error initializing chat: ", e$message)
      }
    )
  })

  # ==== SAMPLE QUESTION HANDLERS ====
  observeEvent(input$ask_mapping, {
    ai_resource_titles(NULL)
    handle_question_button("What resources are about mapping or GIS?", chat_obj)
  })

  observeEvent(input$ask_genai, {
    ai_resource_titles(NULL)
    handle_question_button(
      "Show me generative AI resources from 2026",
      chat_obj
    )
  })

  observeEvent(input$ask_scraping, {
    ai_resource_titles(NULL)
    handle_question_button(
      "What web scraping tutorials are available?",
      chat_obj
    )
  })

  # ==== FREE-FORM USER QUERY HANDLER ====
  observeEvent(input$resource_chat_user_input, {
    req(input$resource_chat_user_input)
    ai_resource_titles(NULL)

    chat <- chat_obj()
    if (is.null(chat)) {
      chat_append(
        "resource_chat",
        "The chat system is not initialized yet. Please wait a moment and try again."
      )
      return()
    }

    user_input <- input$resource_chat_user_input
    prev_totals <- get_cumulative_tokens(chat)

    tryCatch(
      {
        response_stream <- chat$stream_async(user_input)
        chat_append("resource_chat", response_stream) %>%
          then(function(result) {
            usage <- calculate_interaction_tokens(chat, prev_totals)
            if (!is.null(usage)) {
              log_api_usage(
                input_tokens = usage$input_tokens,
                output_tokens = usage$output_tokens,
                model = "gemini-2.5-flash",
                key_source = key_source()
              )
            }
          }) %>%
          catch(function(error) {
            chat_append(
              "resource_chat",
              paste("Sorry, I encountered an error:", error$message)
            )
          })
      },
      error = function(e) {
        chat_append(
          "resource_chat",
          paste("Sorry, I encountered an error:", e$message)
        )
      }
    )
  })

  # ==== FILTER BUTTON UI ====
  output$show_in_table_button <- renderUI({
    titles <- ai_resource_titles()
    if (is.null(titles) || length(titles) == 0) {
      return(NULL)
    }

    current_filter <- table_filter()

    if (is.null(current_filter)) {
      div(
        style = "background: #e3f2f0; padding: 10px; border-radius: 8px; border: 1px solid #2E86AB;",
        actionButton(
          "show_in_table",
          paste("See These", length(titles), "Resources in Table"),
          icon = icon("table"),
          class = "btn-conference",
          style = "width: 100%;"
        )
      )
    } else {
      div(
        style = "background: #fff3cd; padding: 10px; border-radius: 8px; border: 1px solid #E8A838;",
        p(
          paste("Showing", length(current_filter), "filtered resources"),
          style = "margin: 0 0 8px 0; font-size: 13px; color: #856404; font-weight: 500;"
        ),
        actionButton(
          "clear_filter",
          "Show All Resources",
          icon = icon("times-circle"),
          class = "btn-warning",
          style = "width: 100%;"
        )
      )
    }
  })

  observeEvent(input$show_in_table, {
    table_filter(ai_resource_titles())
  })

  observeEvent(input$clear_filter, {
    table_filter(NULL)
  })

  # ==== RENDER TABLE ====
  output$resource_table <- renderReactable({
    data <- resources_data()

    # Apply filter if set
    filter_titles <- table_filter()
    if (!is.null(filter_titles)) {
      data <- data |> filter(What %in% filter_titles)
    }

    reactable(
      data,
      elementId = "resource_table",
      defaultSorted = list(Year = "desc", What = "asc"),
      columns = list(
        # What column: clickable link to URL
        What = colDef(
          name = "Resource",
          minWidth = 280,
          html = TRUE,
          cell = function(value, index) {
            url <- data$URL[index]
            if (!is.na(url) && nzchar(url)) {
              sprintf(
                '<a href="%s" target="_blank" class="cell-title" title="Open resource">%s</a>',
                htmltools::htmlEscape(url, attribute = TRUE),
                htmltools::htmlEscape(value)
              )
            } else {
              sprintf(
                '<span class="cell-title">%s</span>',
                htmltools::htmlEscape(value)
              )
            }
          }
        ),
        # Who column
        Who = colDef(
          name = "Contributors",
          minWidth = 160,
          class = "cell-who"
        ),
        # Year column with color coding and dropdown filter
        Year = colDef(
          name = "Year",
          width = 70,
          align = "center",
          class = function(value) paste0("year-", value),
          filterable = TRUE,
          filterInput = function(values, name) {
            tags$select(
              onchange = sprintf(
                "Reactable.setFilter('resource_table', '%s', event.target.value || undefined)",
                name
              ),
              tags$option(value = "", "All"),
              tags$option(value = "2026", "2026"),
              tags$option(value = "2025", "2025"),
              tags$option(value = "2024", "2024")
            )
          },
          filterMethod = JS(
            "function(rows, columnId, filterValue) {
            return rows.filter(function(row) {
              return String(row.values[columnId]) === filterValue;
            })
          }"
          )
        ),
        # Tags column - compact
        Tags = colDef(
          name = "Tags",
          minWidth = 150,
          class = "cell-tags"
        ),
        # Type column with dropdown filter
        Type = colDef(
          name = "Type",
          width = 130,
          class = "cell-type",
          filterable = TRUE,
          filterInput = function(values, name) {
            tags$select(
              onchange = sprintf(
                "Reactable.setFilter('resource_table', '%s', event.target.value || undefined)",
                name
              ),
              tags$option(value = "", "All"),
              tags$option(value = "Presentation", "Presentation/Repo"),
              tags$option(value = "Tool", "Tool/Software"),
              tags$option(value = "Work Samples", "Work Samples")
            )
          },
          filterMethod = JS(
            "function(rows, columnId, filterValue) {
            return rows.filter(function(row) {
              return String(row.values[columnId]).indexOf(filterValue) !== -1;
            })
          }"
          ),
          # Shorten the long type name for display
          cell = function(value) {
            if (value == "Presentation, Workshop, Repo or Tip Sheet") {
              "Presentation/Repo"
            } else if (value == "Tool, Software or Resource") {
              "Tool/Software"
            } else {
              value
            }
          }
        ),
        # Hidden columns (searchable)
        URL = colDef(show = FALSE, filterable = FALSE),
        AdditionalComments = colDef(show = FALSE, searchable = TRUE, filterable = FALSE)
      ),
      # Expandable row detail: shows Additional Comments
      details = function(index) {
        resource <- data[index, ]
        comments <- resource$AdditionalComments

        # Only show detail if there are comments
        if (is.na(comments) || comments == "") {
          return(div(
            style = "padding: 15px; background: #f8f9fa; border-left: 4px solid #2E86AB;",
            p(
              em("No additional comments for this resource."),
              style = "color: #888; margin: 0;"
            )
          ))
        }

        div(
          style = "padding: 15px; background: #f8f9fa; border-left: 4px solid #2E86AB;",
          div(
            style = "margin-bottom: 10px; padding: 12px; background: white; border-radius: 5px;",
            p(
              strong("Additional Comments:"),
              style = "margin: 0 0 6px 0; color: #1B3A4B;"
            ),
            p(
              comments,
              style = "line-height: 1.6; color: #333; margin: 0;"
            )
          ),
          if (!is.na(resource$URL) && nzchar(resource$URL)) {
            div(
              style = "text-align: right;",
              a(
                "Open Resource",
                href = resource$URL,
                target = "_blank",
                class = "btn btn-sm",
                style = "background-color: #2E86AB; border-color: #2E86AB; color: white;"
              )
            )
          }
        )
      },
      searchable = TRUE,
      searchMethod = JS(
        "function(rows, columnIds, searchValue) {
        var pattern;
        var useRegex = true;
        try {
          pattern = new RegExp(searchValue, 'i');
        } catch (e) {
          useRegex = false;
        }
        return rows.filter(function(row) {
          return columnIds.some(function(columnId) {
            var cellValue = String(row.values[columnId]).toLowerCase();
            if (useRegex) {
              return pattern.test(cellValue);
            } else {
              return cellValue.includes(searchValue.toLowerCase());
            }
          })
        })
      }"
      ),
      language = reactableLang(
        searchPlaceholder = "Search resources (regex supported in this field but not column filters below)"
      ),
      filterable = TRUE,
      highlight = TRUE,
      bordered = TRUE,
      striped = FALSE,
      pagination = TRUE,
      defaultPageSize = 15,
      showPageSizeOptions = TRUE,
      pageSizeOptions = c(15, 30, 50, 100),
      theme = table_theme
    )
  })

  # ==== TABLE STATS ====
  output$table_stats <- renderText({
    data <- resources_data()
    filter_titles <- table_filter()

    if (!is.null(filter_titles)) {
      paste0(
        "Showing ",
        length(filter_titles),
        " of ",
        nrow(data),
        " resources (filtered)"
      )
    } else {
      total <- nrow(data)
      y2024 <- sum(data$Year == 2024, na.rm = TRUE)
      y2025 <- sum(data$Year == 2025, na.rm = TRUE)
      y2026 <- sum(data$Year == 2026, na.rm = TRUE)

      paste0(
        total,
        " Total Resources\n",
        "2024: ",
        y2024,
        " | 2025: ",
        y2025,
        " | 2026: ",
        y2026
      )
    }
  })
}

shinyApp(ui = ui, server = server)
