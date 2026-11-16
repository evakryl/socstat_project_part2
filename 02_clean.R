#02_clean.R
#what it does: turns the four raw files into one tidy country-month panel (beneficiaries, population, per 1000) and one country-level table with the two pre-war community measures.
#what it reads:  data/raw/*.csv
#what it writes: panel_monthly.rds, prewar_country.rds
#author: Yeva (with the help of AI, more details in disclosure)

source(here::here("R", "00_config.R"))

read_raw <- function(name) {
  read_csv(raw_path(name), show_col_types = FALSE, guess_max = 100000) |>
    mutate(time = as.Date(time))
}

#monthly beneficiaries
#computing total sex and age, unit "persons", one row per country and month.
temp_raw <- read_raw("temp_protection")
print_codes <- function(df, col) paste(sort(unique(df[[col]])), collapse = ", ")

beneficiaries <- temp_raw |>
  filter(sex == "T", age == "TOTAL", unit == "PER", is_country_code(geo)) |>
  filter(time >= start_month, time <= end_month) |>
  select(geo, time, beneficiaries = values, flag)
check_not_empty(
  beneficiaries,
  paste0("migr_asytpsm; codes found: sex = ", print_codes(temp_raw, "sex"),
         "; age = ", print_codes(temp_raw, "age"),
         "; unit = ", print_codes(temp_raw, "unit"))
)

#complete(): a country with no row in some month gets an explicit NA row, so gaps are visible instead of silently missing. Duplicate rows would break the one-row-per-country-month rule, so we check for them.
months <- seq(start_month, end_month, by = "month")
stopifnot(!anyDuplicated(beneficiaries[c("geo", "time")]))
beneficiaries <- beneficiaries |>
  complete(geo, time = months)
stopifnot(nrow(beneficiaries) == n_distinct(beneficiaries$geo) * length(months))

#finding the population on 1 January
#the per-1,000 measure of a month uses population on 1 January of that year.
pop_raw <- read_raw("population")
population <- pop_raw |>
  filter(sex == "T", age == "TOTAL", unit == "NR", is_country_code(geo)) |>
  filter(time %in% population_dates) |>
  transmute(geo, year = year(time), population = values)
check_not_empty(population, "demo_pjan")
stopifnot(!anyDuplicated(population[c("geo", "year")]))

#joining and checking that the join neither drops nor duplicates rows
rows_before <- nrow(beneficiaries)
panel <- beneficiaries |>
  mutate(year = year(time)) |>
  left_join(population, by = c("geo", "year"))
stopifnot(nrow(panel) == rows_before)

panel <- panel |>
  mutate(per_1000 = beneficiaries / population * 1000) |>
  select(geo, time, beneficiaries, flag, population, per_1000)

#countries without population data would get NA in per_1000
no_population <- panel |> filter(is.na(population)) |> distinct(geo)
if (nrow(no_population) > 0) {
  message("No population for: ", paste(no_population$geo, collapse = ", "))
}

#pre-war community compited in two measures
citizens <- read_raw("citizens") |>
  filter(sex == "T", age == "TOTAL", is_country_code(geo), time == prewar_citizens_date) |>
  select(geo, citizens = values)
permits <- read_raw("permits") |>
  filter(reason == "TOTAL", duration == "TOTAL", is_country_code(geo),
         time == prewar_permits_date) |>
  select(geo, permits = values)
check_not_empty(citizens, "migr_pop1ctz (Ukrainian citizens, 1 January 2022)")
check_not_empty(permits, "migr_resvalid (all reasons, all durations, 2021)")

pop_2022 <- population |> filter(year == 2022) |> select(geo, population)

prewar_country <- panel |>
  distinct(geo) |>
  left_join(citizens, by = "geo") |>
  left_join(permits, by = "geo") |>
  left_join(pop_2022, by = "geo") |>
  mutate(
    citizens_per_1000 = citizens / population * 1000,
    permits_per_1000 = permits / population * 1000
  )
stopifnot(nrow(prewar_country) == n_distinct(panel$geo))

write_rds(panel, processed_path("panel_monthly.rds"))
write_rds(prewar_country, processed_path("prewar_country.rds"))
message("Panel: ", nrow(panel), " rows, ", n_distinct(panel$geo), " countries")
