# 04_missing_data.R
# hat it does: sub-question 2. maps which country-months are missing or flagged, then builds three versions of the monthly series: "published" (as downloaded), "excluded" (flagged cells and
#large one-month falls set to missing) and "filled" (excluded, then gaps of up to max_gap_months interpolated) and then it repeats this for three thresholds as a sensitivity check.
#what it reads: panel_monthly.rds
#what it writes: panel_versions.rds, panel_filled_by_threshold.rds, panel_filled_strict.rds, missing_data_counts.csv, fig_missingness_grid.png
# Author: Yeva (with the help of AI, more details in disclosure)

source(here::here("R", "00_config.R"))

panel <- read_rds(processed_path("panel_monthly.rds"))

#making linear interpolation inside a country's series. zoo::na.approx needs at least two observed values, so a country with fewer is returned unchanged.
fill_short_gaps <- function(x, max_gap) {
  if (sum(!is.na(x)) < 2) return(x)
  zoo::na.approx(x, maxgap = max_gap, na.rm = FALSE)
}

#applies the missing-data rules to the panel with one drop threshold. here we compare each month with the previous published month: a fall of more than the threshold is more likely a register clean-up than people leaving.
apply_rules <- function(panel, threshold, flag_pattern = flag_exclude_main) {
  panel |>
    arrange(geo, time) |>
    group_by(geo) |>
    mutate(
      published = beneficiaries,
      flagged = if (is.na(flag_pattern)) {
        FALSE
      } else {
        coalesce(str_detect(flag, flag_pattern), FALSE)
      },
      big_fall = coalesce(published / lag(published) - 1 < -threshold, FALSE),
      excluded = if_else(flagged | big_fall, NA_real_, published),
      filled = fill_short_gaps(excluded, max_gap_months)
    ) |>
    ungroup() |>
    mutate(across(
      c(published, excluded, filled),
      ~ .x / population * 1000,
      .names = "{.col}_per_1000"
    ))
}

versions_main <- apply_rules(panel, drop_threshold)
stopifnot(nrow(versions_main) == nrow(panel))

#making all of it in long format, one row per country, month and version, for later scripts.
panel_versions <- versions_main |>
  select(geo, time, population, published, excluded, filled) |>
  pivot_longer(
    c(published, excluded, filled),
    names_to = "version", values_to = "beneficiaries") |>
  mutate(per_1000 = beneficiaries / population * 1000)
write_rds(panel_versions, processed_path("panel_versions.rds"))

#checking sensitivity, how many cells each threshold removes or fills, to be exact
by_threshold <- map(drop_thresholds_sensitivity, function(threshold) {
  apply_rules(panel, threshold) |> mutate(threshold = threshold)
}) |>
  list_rbind()

#strict sensitivity: additionally drop every cell flagged "d". so, this removes whole countries (France, Spain, Greece, Cyprus) and Germany until mid-2024.
strict <- apply_rules(panel, drop_threshold, flag_exclude_strict)
strict |>
  select(geo, time, population, filled) |>
  write_rds(processed_path("panel_filled_strict.rds"))

missing_data_counts <- bind_rows(
  by_threshold |> mutate(rule = "fall rule only"),
  strict |> mutate(threshold = drop_threshold, rule = "fall rule + flag d")) |>
  group_by(rule, threshold) |>
  summarise(
    cells = n(),
    missing_in_published = sum(is.na(published)),
    flagged = sum(flagged),
    big_falls = sum(big_fall),
    filled_by_interpolation = sum(is.na(excluded) & !is.na(filled)),
    still_missing = sum(is.na(filled)),
    .groups = "drop")
write_csv(missing_data_counts, table_path("missing_data_counts.csv"))

by_threshold |>
  select(geo, time, population, threshold, filled) |>
  write_rds(processed_path("panel_filled_by_threshold.rds"))

#missingness grid
status_levels <- c("reported", "filled by interpolation",
                   "excluded (flag or fall)", "missing")
grid <- versions_main |>
  mutate(status = case_when(
    !is.na(excluded) ~ "reported",
    !is.na(filled) ~ "filled by interpolation",
    !is.na(published) ~ "excluded (flag or fall)",
    TRUE ~ "missing"
  )) |>
  mutate(status = factor(status, levels = status_levels))

#countries ordered by the first month with a published value.
country_order <- grid |>
  group_by(geo) |>
  summarise(first = first_observed(time, published), .groups = "drop") |>
  arrange(desc(first), desc(geo)) |>
  pull(geo)

fig_grid <- grid |>
  mutate(geo = factor(geo, levels = country_order)) |>
  ggplot(aes(time, geo, fill = status)) +
  geom_tile() +
  scale_fill_manual(
    values = c("reported" = "grey80", "filled by interpolation" = "green3",
               "excluded (flag or fall)" = "orange2", "missing" = "red3"),
    drop = FALSE) +
  labs(
    x = NULL, y = NULL, fill = NULL,
    title = "Which country-months are usable?",
    subtitle = paste0("Fall threshold ", drop_threshold * 100, "%, gaps up to ",
                      max_gap_months, " months interpolated")) +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave(figure_path("fig_missingness_grid.png"), fig_grid, width = 9, height = 7, dpi = 150)
