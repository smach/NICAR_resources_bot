# NICAR 2024-2026 Public Resources Explorer

This repo contains code for an R Shiny app for to find resources from NICAR data journalism conferences that have been made public. It features a chatbot that answers natural language questions about the resources, as well as a searchable, filterable table.

This app was built using the same architecture as the [NICAR 2026 Session Explorer](https://github.com/smach/NICAR2026_chatbot), which has a chatbot and searchable table for the NICAR 2026 conference schedule. It took me a fair amount of time, and back & forth with Claude, to get that app right. However, re-purposing that idea and code for this slightly different data took very little additional time and effort. This is one of my favorite types of generative AI use cases: Re-use existing code you like for other data!

Note: [My database of NICAR conference resources](https://apps.machlis.com/shiny/nicar20_resources/) goes back to 2020. However, because a fair amount has changed in the technical coding space recently, I decided to stick to 2024-2026 for this.

The rest of this README below was written largely by Claude and lightly edited by me.

## Features

- **AI-Powered Chat**: Ask natural language questions to find relevant resources
- **Topic Search**: Semantic search for resources by topic (e.g., "mapping tutorials", "web scraping")
- **Contributor Search**: Keyword-based search for resources by presenter name
- **Year & Tag Filtering**: Filter by conference year, tags, and resource type via the chatbot
- **Filter Button**: After AI finds resources, click to filter the table to just those results
- **Interactive Table**: Browse all resources with search, sort, and column filters
- **Clickable Titles**: Resource titles link directly to the original material
- **Expandable Details**: Click any row to see Additional Comments
- **Column Filters**: Dropdown filters for Year (2024/2025/2026) and Type (Presentation/Tool/Work Samples)

## Data

The resource data comes from a spreadsheet of publicly shared NICAR conference materials I've been maintaining with the help of many people sending me resources to add, including presentations, workshops, tip sheets, tools, and repos. Each resource includes:

- **What**: Resource title as a clickable link
- **Who**: Creators/presenters
- **Year**: Conference year (2024, 2025, or 2026)
- **Tags**: Topic tags (e.g., #python, #genai, #gis, #rstats)
- **Type**: Presentation/Workshop/Repo, Tool/Software, or Work Samples
- **Additional Comments**: Extra context or related links

## Requirements

### R Version
- R 4.1.0 or higher recommended

### Required Packages
```r
install.packages(c("shiny", "bslib", "reactable", "dplyr", "arrow",
                    "htmltools", "htmlwidgets", "promises", "DBI"))

# Install from GitHub (development versions)
pak::pak("posit-dev/shinychat")
pak::pak("posit-dev/ellmer")
pak::pak("posit-dev/ragnar")
```

### API Keys
You need a **Google Gemini API key** for the chat functionality. Google has a free tier for Gemini 2.5 Flash, so you can try it out locally for free.

If you want to regenerate the ragnar data store from scratch, you'll also need an **OpenAI API key** for the text embeddings.

```r
# Set in .Renviron file
GEMINI_API_KEY=your-key-here

# Or set in R session
Sys.setenv(GEMINI_API_KEY = "your-key-here")
```

If no key is set, the app will prompt you to enter one at startup.

## Setup

### 1. Build the Data Store (optional)
The repo includes pre-built data files. If you want to rebuild from the CSV (e.g., after adding new resources), run:

```r
source("01_prepare_data.R")
```

This creates:
- `nicar_resources.duckdb` - Ragnar vector store with embeddings
- `resources_for_app.parquet` - Resource data for the table display

This requires an OpenAI API key for generating embeddings.

### 2. Run the App
```r
shiny::runApp()
```

Or in RStudio or Positron, open `app.R` and click the run icon.

### Note on Usage Logging

The app includes optional API usage logging for cost monitoring. **Both local and cloud logging are disabled by default.**

- **To enable local CSV logging**: Set `NICAR_CHATBOT_LOG_USAGE=true` in your `.Renviron` file. Logs are saved to the `logs/` directory.
- **To enable Supabase cloud logging**: Set `SUPABASE_URL` and `SUPABASE_KEY` in `.Renviron`, then uncomment the `log_to_supabase()` call in `helpers_logging.R`.

**Only token counts and calculated costs are logged.** No queries, user data, or API keys are ever saved.

## File Structure

| File | Description |
|------|-------------|
| `app.R` | Main Shiny application with UI and server logic |
| `helpers_ui.R` | UI components, styling, and themes |
| `helpers_server.R` | Server helper functions for chat handling |
| `helpers_logging.R` | Optional API usage logging |
| `01_prepare_data.R` | Data processing pipeline (run once to set up) |
| `resources.csv` | Source data: community-maintained resource list |
| `nicar_resources.duckdb` | Ragnar vector store with resource embeddings |
| `resources_for_app.parquet` | Resource data for table display |
| `test_data_prep.R` | Test script for validating data preparation |

## Usage

### Chat Interface
Ask questions like:
- "What resources are about mapping or GIS?"
- "Show me generative AI resources from 2026"
- "What web scraping tutorials are available?"
- "Show me R resources for beginner or intermediate users from this year."

### Filter Button
After the AI finds resources, a **"See These [number] Resources in Table"** button appears. Click it to filter the table to just those resources. A **"Show All Resources"** button lets you clear the filter.

### Table
- **Search**: Use the search box to filter across all columns including hidden Additional Comments (regex supported)
- **Column Filters**: Use the Year and Type dropdowns to filter
- **Sort**: Click column headers to sort (default: Year descending, then Resource title ascending)
- **Click Titles**: Resource titles are clickable links to the original material
- **Expand Rows**: Click the expander triangle to see Additional Comments

## How It Works

1. **Data Processing**: Resource data from `resources.csv` is cleaned (tags normalized to lowercase, duplicates removed), then embedded using OpenAI's text-embedding-3-small model via the ragnar R package.

2. **RAG Search**: The app uses ragnar's search capabilities:
   - **Vector Similarity Search (VSS)** for semantic matching on resource titles and descriptions
   - **BM25 keyword matching** for contributor name searches
   - **Metadata filtering** for year, type, and tag constraints

3. **Tool Calling**: The AI has three tools:
   - `search_resources` - Topic-based semantic search with optional filters for year, type, and tags
   - `search_by_contributor` - Keyword search for resources by contributor name
   - `highlight_resources` - Enables the "Show in Table" filter button

4. **Tag Searching**: Tags are stored as lowercase strings (e.g., `"#python, #scraping, #apis"`). The chatbot filters by tag using substring matching, so searching for `#python` correctly matches resources with multiple tags.

## Credits

- **Conference**: [NICAR](https://www.ire.org/training/conferences/nicar-2026/) by IRE (Investigative Reporters and Editors)
- **Based on**: [NICAR 2026 Session Explorer](https://github.com/smach/NICAR2026_chatbot) also by Claude and me
- **Packages**: [shinychat](https://github.com/posit-dev/shinychat), [ellmer](https://github.com/posit-dev/ellmer), [ragnar](https://github.com/posit-dev/ragnar) by Posit
- **AI**: Google Gemini 2.5 Flash for chat, OpenAI text-embedding-3-small for embeddings, Claude for writing much of the code

## Disclaimer

This is an **unofficial** app! AI can make mistakes. Always verify resource links before relying on them.
