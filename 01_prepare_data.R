library(dplyr)
library(ragnar)
library(stringr)

# Read the CSV
resources_df <- rio::import("resources.csv")

# Clean column names for easier handling
colnames(resources_df) <- c(
  "Timestamp", "Year", "What", "Who", "URL", "Tags", "Type", "AdditionalComments"
)

# Drop Timestamp, clean data
resources_df <- resources_df |>
  select(-Timestamp) |>
  mutate(
    # Clean stray quotes from CSV parsing artifacts
    across(where(is.character), \(x) str_remove_all(x, '^"+|"+$')),
    across(where(is.character), str_trim),
    Year = as.integer(Year),
    # Normalize tags: lowercase, clean up spacing
    Tags = Tags |>
      str_to_lower() |>
      # Split on commas or spaces (between tags), normalize
      str_replace_all(",\\s*", ", ") |>
      str_replace_all("\\s+#", " #") |>
      str_trim(),
    # Fill missing Type values
    Type = if_else(is.na(Type) | Type == "", "Unspecified", Type),
    # Clean up AdditionalComments NAs
    AdditionalComments = if_else(
      is.na(AdditionalComments), "", AdditionalComments
    )
  )

# Deduplicate tags within each row (e.g. #ai appears twice due to case)
deduplicate_tags <- function(tag_string) {
  if (is.na(tag_string) || tag_string == "") return("")
  tags <- str_split(tag_string, "[,\\s]+")[[1]]
  tags <- tags[tags != ""]
  tags <- unique(tags)
  paste(tags, collapse = ", ")
}

resources_df <- resources_df |>
  mutate(Tags = vapply(Tags, deduplicate_tags, character(1), USE.NAMES = FALSE))

glimpse(resources_df)

# Create text for embedding: What + Additional Comments (primary search fields)
# Also include Who and Tags for richer semantic matching
resources_chunks <- resources_df |>
  mutate(
    text = paste0(
      "### ", What, "\n\n",
      "Contributors: ", Who, "\n",
      "Year: ", Year, "\n",
      "Tags: ", Tags, "\n",
      "Type: ", Type, "\n",
      if_else(
        AdditionalComments != "",
        paste0("\n", AdditionalComments, "\n"),
        ""
      )
    ),
    context = What
  ) |>
  arrange(desc(Year), What)

# Export parquet for app table display
resources_for_app <- resources_df |>
  arrange(desc(Year), What)

rio::export(resources_for_app, "resources_for_app.parquet")

# Define extra metadata columns for the ragnar store
my_extra_columns <- data.frame(
  What = character(),
  Who = character(),
  URL = character(),
  Year = integer(),
  Tags = character(),
  Type = character(),
  AdditionalComments = character()
)

store_file_location <- "nicar_resources.duckdb"

# Create the ragnar vector store
store <- ragnar_store_create(
  store_file_location,
  embed = \(x) ragnar::embed_openai(x, model = "text-embedding-3-small"),
  extra_cols = my_extra_columns,
  overwrite = TRUE,
  version = 1
)

# Insert chunks
ragnar_store_insert(store, resources_chunks)

# Build the store index
ragnar_store_build_index(store)

# Inspect
chunks_in_store <- tbl(store@con, "chunks") |>
  select(-embedding) |>
  collect()

cat("Stored", nrow(chunks_in_store), "resources in the vector store\n")

# Install and load FTS extension (needed on Windows)
DBI::dbExecute(store@con, "INSTALL fts;")
DBI::dbExecute(store@con, "LOAD fts;")

# Disconnect
DBI::dbDisconnect(store@con, shutdown = TRUE)

cat("Done! Created resources_for_app.parquet and nicar_resources.duckdb\n")
