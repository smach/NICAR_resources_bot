header_content <- div(
  class = "header-content",
  a(
    href = "https://github.com/smach/NICAR_resources_bot",
    target = "_blank",
    title = "View source on GitHub",
    class = "github-link",
    icon("github", lib = "font-awesome"),
    style = "position: absolute; top: 15px; right: 20px; color: #ffffff; font-size: 24px; opacity: 0.8; transition: opacity 0.2s;"
  ),
  h1(
    "NICAR 2024-2026 Public Resources Explorer",
    style = "margin: 0; font-weight: 300; font-size: 2rem;"
  ),
  p(
    "AI-Powered Resource Discovery for NICAR Conference Materials",
    style = "margin: 6px 0; font-size: 15px; opacity: 0.9;"
  ),
  p(
    "AI can make mistakes - always verify resource links",
    style = "margin: 6px 0 0 0; font-size: 12px; opacity: 0.7;"
  )
)

chatbot_welcome <- "Welcome to the NICAR Resources Explorer! I can help you find conference resources from 2024-2026. Ask me about topics, tools, contributors, or filter by year and tags. What are you looking for?"

custom_style <- HTML(
  "
    /* ---------- HEADER ---------- */
    .header-section {
      background: #1B3A4B;
      color: #ffffff;
      padding: 12px 20px;
      margin: -15px -15px 8px -15px;
      text-align: center;
      position: relative;
    }

    .github-link:hover {
      opacity: 1 !important;
      color: #E8A838 !important;
    }

    .header-content { text-align: center; }

    /* ---------- CHAT SIDEBAR ---------- */
    .chat-sidebar {
      background: #ffffff !important;
      border: 1px solid #e0e0e0;
      border-radius: 5px;
      padding: 10px;
    }

    .shinychat-message-assistant .shinychat-message-content {
      background-color: #ffffff !important;
      color: #1B3A4B !important;
      border: 1px solid #d0d0d0 !important;
      padding: 10px 12px !important;
      border-radius: 6px !important;
      margin: 6px 0 !important;
      font-size: 14px !important;
      line-height: 1.5 !important;
    }

    .shinychat-message-user .shinychat-message-content {
      background-color: #f0f0f0 !important;
      color: #1B3A4B !important;
      border: 1px solid #d0d0d0 !important;
      padding: 10px 12px !important;
      border-radius: 6px !important;
      margin: 6px 0 !important;
      font-size: 14px !important;
      line-height: 1.5 !important;
    }

    .shinychat-messages h1,
    .shinychat-messages h2,
    .shinychat-messages h3,
    .shinychat-messages h4,
    .shinychat-messages h5,
    .shinychat-messages h6 {
      color: #1B3A4B !important;
      font-weight: 600 !important;
    }

    .shinychat-messages ul,
    .shinychat-messages ol {
      color: #1B3A4B !important;
      padding-left: 16px !important;
      margin: 4px 0 !important;
    }

    .shinychat-messages li {
      color: #1B3A4B !important;
      margin-bottom: 4px !important;
    }

    .shinychat-messages p {
      margin: 4px 0 !important;
    }

    /* ---------- SAMPLE QUESTION BUTTONS ---------- */
    .btn-sample-questions {
      width: 100%;
      margin-bottom: 8px;
      white-space: normal;
      text-align: left;
      background-color: #1B3A4B !important;
      color: #ffffff !important;
      border: 2px solid #1B3A4B !important;
      padding: 10px 15px;
      font-size: 14px;
      font-weight: 500;
      transition: all 0.2s ease;
    }

    .btn-sample-questions:hover {
      background-color: #0f2433 !important;
      border-color: #0f2433 !important;
      color: #ffffff !important;
      transform: translateY(-1px);
      box-shadow: 0 2px 4px rgba(0,0,0,0.2);
    }

    .btn-sample-questions:focus {
      outline: 3px solid #E8A838 !important;
      outline-offset: 2px;
    }

    /* ---------- OTHER BUTTONS ---------- */
    .btn-conference {
      background-color: #2E86AB;
      border-color: #2E86AB;
      color: #ffffff;
      font-weight: 500;
    }
    .btn-conference:hover {
      background-color: #236d8c;
      border-color: #236d8c;
    }

    .btn-warning {
      background-color: #E8A838;
      border-color: #E8A838;
      color: #1B3A4B;
      font-weight: 500;
    }
    .btn-warning:hover {
      background-color: #d19530;
      border-color: #d19530;
      color: #1B3A4B;
    }

    /* ---------- STATS BOX ---------- */
    .stats-box {
      background: #D4E8E0;
      color: #1B3A4B;
      padding: 10px;
      border-radius: 5px;
      font-weight: 600;
    }

    /* ---------- SECTION HEADERS ---------- */
    h5 {
      color: #1B3A4B !important;
      font-weight: 600 !important;
    }

    /* ---------- REACTABLE CELL STYLES ---------- */
    .year-2024 { color: #2E86AB; font-weight: 600; }
    .year-2025 { color: #E8A838; font-weight: 600; }
    .year-2026 { color: #A23B72; font-weight: 600; }

    .cell-title { font-weight: 600; color: #1B3A4B; white-space: normal; line-height: 1.4; }
    .cell-title a { color: #1B3A4B; text-decoration: none; }
    .cell-title a:hover { color: #2E86AB; text-decoration: underline; }
    .cell-who { font-size: 13px; color: #555; white-space: normal; line-height: 1.3; }
    .cell-tags { font-size: 12px; color: #666; white-space: normal; line-height: 1.4; }
    .cell-type { font-size: 13px; color: #666; }

    /* ---------- CHAT INPUT ---------- */
    .shiny-input-container input[type='text'] {
      border: 2px solid #e0e0e0;
      font-size: 14px;
      padding: 8px 12px;
    }

    .shiny-input-container input[type='text']:focus {
      border-color: #2E86AB;
      outline: none;
      box-shadow: 0 0 0 3px rgba(46, 134, 171, 0.1);
    }
  "
)


custom_theme <- bs_theme(
  bootswatch = "flatly",
  primary = "#2E86AB",
  bg = "#ffffff",
  fg = "#1B3A4B",
  base_font = font_google("Source Sans Pro")
)

table_theme <- reactableTheme(
  searchInputStyle = list(
    width = "100%",
    backgroundColor = "#ffffff",
    border = "2px solid #e0e0e0",
    borderRadius = "4px",
    padding = "8px 12px",
    fontSize = "14px"
  ),
  headerStyle = list(
    background = "#D4E8E0",
    color = "#1B3A4B",
    fontWeight = "600",
    fontSize = "14px"
  ),
  rowStyle = list(
    cursor = "pointer",
    "&:hover" = list(background = "#f0f8f6")
  )
)
