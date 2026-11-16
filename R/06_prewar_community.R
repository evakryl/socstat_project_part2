# 06_prewar_community.R ---------------------------------------------------
# What it does: sub-question 3, first part. Marks countries whose pre-war
#               citizenship count is probably under-reported, fills those
#               values by multiple imputation (using the permits measure),
#               and computes Spearman correlations between each pre-war
#               measure and beneficiaries per 1,000 in each December, with
#               and without Poland.
# Reads:  data/processed/panel_versions.rds, data/processed/prewar_country.rds
# Writes: data/processed/prewar_measures.rds, outcome_december.rds,
#         output/tables/under_reported_countries.csv,
#         correlations_prewar.csv,
#         output/figures/fig_correlations_by_date.png, fig_scatter_prewar.png
# Author: Victoriya

source(here::here("R", "00_config.R"))
# mice is not attached: it masks dplyr::filter(). Its functions are called with mice::.

panel_versions <- read_rds(processed_path("panel_versions.rds"))
prewar <- read_rds(processed_path("prewar_country.rds"))

# Outcome: beneficiaries per 1,000 in each December (one version of the series).
outcome <- panel_versions |>
  filter(version == outcome_version, time %in% december_dates) |>
  select(geo, time, outcome_per_1000 = per_1000)
write_rds(outcome, processed_path("outcome_december.rds"))

# Under-reporting rule ------------------------------------------------------
# Where many Ukrainians held short-term permits, the citizenship stock can be
# low compared with permits. The ratio citizens / permits below a share of
# the median ratio marks such countries (Slovakia, Lithuania, Hungary); their
# citizenship value is set to missing and imputed from permits. Eight
# countries (including Poland) have no published citizenship value at all and
# are imputed in the same step.
prewar_flagged <- prewar |>
  mutate(ratio = if_else(permits > 0, citizens / permits, NA_real_))
median_ratio <- median(prewar_flagged$ratio, na.rm = TRUE)
prewar_flagged <- prewar_flagged |>
  mutate(
    under_reported = !is.na(ratio) & ratio < underreport_ratio * median_ratio,
    citizens_clean = if_else(under_reported, NA_real_, citizens_per_1000)
  )
write_csv(
  prewar_flagged |>
    select(geo, citizens, permits, ratio, under_reported) |>
    arrange(ratio),
  table_path("under_reported_countries.csv")
)

# Multiple imputation -------------------------------------------------------
# Only countries with a permits value can be imputed. Both variables are put
# on a log scale (log1p keeps zeros) because per-1,000 values are very skewed.
# Method "norm" (Bayesian linear regression) is used because with about 30
# countries the default predictive mean matching has very few donors.
to_impute <- prewar_flagged |> filter(!is.na(permits_per_1000))
imputation_data <- data.frame(
  log_permits = log1p(to_impute$permits_per_1000),
  log_citizens = log1p(to_impute$citizens_clean)
)

set.seed(seed)
imputations <- mice::mice(
  imputation_data,
  m = n_imputations, method = "norm", seed = seed, printFlag = FALSE
)

imputed_long <- map(seq_len(n_imputations), function(k) {
  tibble(
    geo = to_impute$geo,
    imputation = k,
    citizens_imputed_per_1000 = expm1(mice::complete(imputations, k)$log_citizens)
  )
}) |>
  list_rbind()

# One value per country for the resampling script: mean over the imputations.
prewar_measures <- prewar_flagged |>
  left_join(
    imputed_long |>
      group_by(geo) |>
      summarise(citizens_imputed_per_1000 = mean(citizens_imputed_per_1000),
                .groups = "drop"),
    by = "geo"
  )
stopifnot(nrow(prewar_measures) == nrow(prewar))
write_rds(prewar_measures, processed_path("prewar_measures.rds"))

# Correlations by December, measure and sample -------------------------------
spearman_r <- function(x, y) {
  complete_pairs <- !is.na(x) & !is.na(y)
  if (sum(complete_pairs) < 3) return(NA_real_)
  cor(x[complete_pairs], y[complete_pairs], method = "spearman")
}

# Every measure in one long table; imputation 0 = a single, non-imputed value.
measure_long <- bind_rows(
  prewar_measures |>
    transmute(geo, measure = "citizens (published)", imputation = 0L,
              x = citizens_per_1000),
  prewar_measures |>
    transmute(geo, measure = "permits", imputation = 0L, x = permits_per_1000),
  imputed_long |>
    transmute(geo, measure = "citizens (imputed)", imputation,
              x = citizens_imputed_per_1000)
)

# Join the outcome of each December separately: many measure rows per country
# against one outcome row per country, so the join is many-to-one.
with_outcome <- map(december_dates, function(december) {
  outcome_one <- outcome |>
    filter(time == december) |>
    select(geo, outcome_per_1000)
  measure_long |>
    left_join(outcome_one, by = "geo") |>
    mutate(date = december)
}) |>
  list_rbind()
stopifnot(nrow(with_outcome) == nrow(measure_long) * length(december_dates))

correlations_by_imputation <- map(c(FALSE, TRUE), function(without_poland) {
  df <- if (without_poland) {
    filter(with_outcome, geo != excluded_country_for_check)
  } else {
    with_outcome
  }
  df |>
    group_by(measure, date, imputation) |>
    summarise(
      r = spearman_r(x, outcome_per_1000),
      n_countries = sum(!is.na(x) & !is.na(outcome_per_1000)),
      .groups = "drop"
    ) |>
    mutate(sample = if (without_poland) "without Poland" else "all countries")
}) |>
  list_rbind()

# For the imputed measure there are n_imputations values per cell: report the
# median and the range, not a single number.
correlations_prewar <- correlations_by_imputation |>
  group_by(measure, sample, date) |>
  summarise(
    r_median = median(r, na.rm = TRUE),
    r_min = min(r, na.rm = TRUE),
    r_max = max(r, na.rm = TRUE),
    n_countries = max(n_countries),
    .groups = "drop"
  )
write_csv(correlations_prewar, table_path("correlations_prewar.csv"))

fig_correlations <- correlations_prewar |>
  mutate(year = format(date, "%Y")) |>
  ggplot(aes(year, r_median, colour = measure, group = measure)) +
  geom_pointrange(aes(ymin = r_min, ymax = r_max),
                  position = position_dodge(width = 0.4)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  facet_wrap(~sample) +
  labs(
    x = "December of", y = "Spearman correlation", colour = "Pre-war measure",
    title = "Pre-war community and beneficiaries per 1,000",
    subtitle = "Bars show the range over imputations (only for the imputed measure)"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave(figure_path("fig_correlations_by_date.png"), fig_correlations,
       width = 9, height = 5, dpi = 150, bg = "white")

# Plain scatter: the simple baseline against which the checks are read.
fig_scatter <- prewar_measures |>
  select(geo, permits_per_1000) |>
  inner_join(outcome, by = "geo") |>
  # Countries without a permits value or without a December value cannot be
  # plotted; dropping them here avoids a ggplot "removed rows" warning.
  drop_na(permits_per_1000, outcome_per_1000) |>
  mutate(year = format(time, "%Y")) |>
  ggplot(aes(permits_per_1000, outcome_per_1000, label = geo)) +
  geom_point(size = 1) +
  # Every country is labelled (no check_overlap, which would hide some).
  geom_text(size = 2.5, vjust = -0.6) +
  # Log scale on x: most countries have fewer than 5 permits per 1,000,
  # so on a plain scale they would sit on top of each other.
  scale_x_log10() +
  facet_wrap(~year, scales = "free_y") +
  labs(
    x = "Valid permits held by Ukrainians, end of 2021, per 1,000 (log scale)",
    y = "Beneficiaries per 1,000 in December",
    title = "A few countries sit far from the rest"
  ) +
  theme_minimal()
ggsave(figure_path("fig_scatter_prewar.png"), fig_scatter, width = 9, height = 6, dpi = 150, bg = "white")
