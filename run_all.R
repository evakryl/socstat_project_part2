# run_all.R ---------------------------------------------------------------
# Entry point of the project. Open the .Rproj, restart R (Session > Restart R)
# and run this file. It runs every script in R/ in order and saves
# sessionInfo() at the end.
#
# Reads:  data/raw/*.csv (or downloads them if rerun_download is TRUE)
# Writes: data/processed/*, output/figures/*, output/tables/*,
#         output/session_info.txt

# TRUE = download the four Eurostat datasets again (needs internet, a few
# minutes). Default FALSE = use the files already in data/raw/.
rerun_download <- FALSE

library(here)
library(purrr)

scripts <- c(
  "01_get_data.R",
  "02_clean.R",
  "03_descriptives.R",
  "04_missing_data.R",
  "05_spatial.R",
  "06_prewar_community.R",
  "07_resampling.R"
)

walk(scripts, function(script) {
  message("Running ", script)
  source(here("R", script), echo = FALSE)
})

writeLines(
  capture.output(sessionInfo()),
  here("output", "session_info.txt")
)
message("Done. Figures are in output/figures, tables in output/tables.")
