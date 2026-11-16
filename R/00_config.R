#00_config.R 
# what it does: loads the shared packages and defines every parameter of the project in one place (dates, thresholds, seeds, file names).
#what it reads: nothing.
#what it writes: nothing (creates the output folders if they are missing).
#every other script starts with source(here::here("R", "00_config.R")).

library(here)
library(tidyverse)

#switch: TRUE downloads the data from Eurostat again (needs internet). default FALSE: the scripts read the files already saved in data/raw/.
if (!exists("rerun_download")) rerun_download <- FALSE
seed <- 20261115

#Germany starts reporting in August 2022, so the common window starts there.
start_month <- as.Date("2022-08-01")
end_month <- as.Date("2025-12-01")
december_dates <- as.Date(c("2022-12-01", "2023-12-01", "2024-12-01", "2025-12-01"))
population_dates <- as.Date(paste0(2022:2025, "-01-01")) # population on 1 January

#here we are computing the pre-war community using eurostat reference dates
prewar_citizens_date <- as.Date("2022-01-01") 
prewar_permits_date <- as.Date("2021-01-01") 

#missing-data rules (sub-question 2)
#no Eurostat flag marks a value as missing in these data (flags seen: b, d, e, dp), and France, Spain, Greece and Cyprus carry "d" ("definition differs") in every month. dropping flagged cells would remove those countries completely, so the main versions use only the fall rule, flag "d" is a strict sensitivity.
flag_exclude_main <- NA_character_ # NA = no flag removes a cell
flag_exclude_strict <- "d"
max_gap_months <- 2 # gaps up to this length are filled by interpolation
drop_threshold <- 0.10 # the month of a fall bigger than this is set to missing
drop_thresholds_sensitivity <- c(0.05, 0.10, 0.20)

#pre-war community rule and imputation for sub-question 3 
underreport_ratio <- 0.5 # citizens/permits below 0.5*median=under-reported
n_imputations <- 20

#resampling for sub-question 3
n_permutations <- 10000
n_bootstrap <- 2000
n_noise_reps <- 500
noise_sds <- c(0, 0.25, 0.5, 1, 1.5) # sd of the multiplicative log-error
excluded_country_for_check <- "PL" # Poland, for the "without Poland" results
outcome_version <- "filled" # which version of the monthly series is used

#spatial
kyiv <- c(lon = 30.5234, lat = 50.4501)
lviv <- c(lon = 24.0297, lat = 49.8397) # second reference point for a robustness check
europe_xlim <- c(-25, 45)
europe_ylim <- c(33, 72)

#file names
raw_files <- c(
  temp_protection = "migr_asytpsm.csv",
  citizens = "migr_pop1ctz.csv",
  permits = "migr_resvalid.csv",
  population = "demo_pjan.csv"
)
raw_path <- function(name) here("data", "raw", raw_files[[name]])
processed_path <- function(file) here("data", "processed", file)
figure_path <- function(file) here("output", "figures", file)
table_path <- function(file) here("output", "tables", file)

walk(
  c(here("data", "raw"), here("data", "processed"),
    here("output", "figures"), here("output", "tables")),
  dir.create,
  recursive = TRUE, showWarnings = FALSE
)

#helpers used by several scripts
#eurostat country codes are two letters; aggregates like EU27_2020 are longer.
is_country_code <- function(geo) nchar(geo) == 2

#first date with a non-missing value; NA if the series is empty. Plain min() would return Inf and warn on an empty series.
first_observed <- function(time, x) {
  if (all(is.na(x))) return(as.Date(NA))
  min(time[!is.na(x)])
}

#stop with a clear message if a filter returned nothing (wrong code values).
check_not_empty <- function(df, what) {
  if (nrow(df) == 0) stop("No rows left after filtering: ", what, call. = FALSE)
  df
}
