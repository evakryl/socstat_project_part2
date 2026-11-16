#01_get_data.R 
#what it does: downloads the four Eurostat datasets with the eurostat package and saves them as csv in data/raw/. skipped unless rerun_download is TRUE; then it only checks the files exist.
#what it reads: Eurostat API (only if rerun_download is TRUE)
#what it writes: migr_asytpsm.csv, migr_pop1ctz.csv, migr_resvalid.csv, demo_pjan.csv, data/raw/download_date.txt
#author: Yeva (with the help of AI, more details in disclosure)

source(here::here("R", "00_config.R"))

#eurostat package versions name the time and flag columns differently, so we renamed them to fixed names ("time", "flag") and add an empty flag column if the dataset has none.
standardise_eurostat <- function(df) {
  df <- df |>
    rename_with(~ "time", any_of(c("TIME_PERIOD", "time"))) |>
    rename_with(~ "flag", any_of(c("OBS_FLAG", "flags")))
  if (!"flag" %in% names(df)) df$flag <- NA_character_
  df |> mutate(time = as.Date(time), flag = as.character(flag))
}

#keepFlags = TRUE, as the quality flags (e.g. "definition differs") are an input of the missing-data analysis. datasets with a citizenship dimension are cut to Ukrainian citizens straight away, because the full files are very large.
download_dataset <- function(id, ukraine_only) {
  message("Downloading ", id, " (this can take a few minutes)")
  df <- eurostat::get_eurostat(
    id,
    time_format = "date", type = "code", keepFlags = TRUE, cache = FALSE
  ) |>
    standardise_eurostat()
  if (ukraine_only) df <- filter(df, citizen == "UA")
  #population: only the total (both sexes, all ages) is used later, so we keep only that and the file stays small.
  if (id == "demo_pjan") df <- filter(df, sex == "T", age == "TOTAL")
  check_not_empty(df, id)
}

if (rerun_download) {
  dataset_ids <- c(
    temp_protection = "migr_asytpsm",
    citizens = "migr_pop1ctz",
    permits = "migr_resvalid",
    population = "demo_pjan"
  )
  ukraine_only <- c(
    temp_protection = TRUE, citizens = TRUE, permits = TRUE, population = FALSE
  )

  walk(names(dataset_ids), function(name) {
    download_dataset(dataset_ids[[name]], ukraine_only[[name]]) |>
      write_csv(raw_path(name))
  })
  write_lines(as.character(Sys.Date()), here("data", "raw", "download_date.txt"))
} else {
  missing_files <- raw_files[!file.exists(map_chr(names(raw_files), raw_path))]
  if (length(missing_files) > 0) {
    stop(
      "Raw data not found: ", paste(missing_files, collapse = ", "),
      ". Set rerun_download <- TRUE in run_all.R once to download them.",
      call. = FALSE
    )
  }
  message("Using the raw files already in data/raw/")
}
