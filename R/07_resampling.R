# 07_resampling.R ---------------------------------------------------------
# What it does: sub-question 3, second part. Checks how solid the Spearman
#               correlations between pre-war community and beneficiaries per
#               1,000 are, with about 30 countries:
#               (a) permutation test, (b) leave-one-out, (c) bootstrap over
#               countries, (d) simulation of measurement error in the
#               pre-war measure.
# Reads:  data/processed/prewar_measures.rds, data/processed/outcome_december.rds
# Writes: output/tables/resampling_summary.csv, leave_one_out_full.csv,
#         noise_simulation.csv,
#         output/figures/fig_resampling_checks.png, fig_noise_simulation.png
# Author: Victoriya

source(here::here("R", "00_config.R"))

prewar_measures <- read_rds(processed_path("prewar_measures.rds"))
outcome <- read_rds(processed_path("outcome_december.rds"))

# The two measures that cover (almost) all countries. The imputed citizenship
# measure is the mean over the imputations of script 06.
measure_columns <- c(
  permits = "permits_per_1000",
  citizens_imputed = "citizens_imputed_per_1000"
)
grid <- expand_grid(measure = names(measure_columns), date = december_dates)

# Complete country pairs (x = pre-war community, y = beneficiaries) ---------
get_pairs <- function(measure_name, date) {
  prewar_measures |>
    select(geo, x = all_of(measure_columns[[measure_name]])) |>
    inner_join(
      outcome |> filter(time == date) |> select(geo, y = outcome_per_1000),
      by = "geo"
    ) |>
    drop_na()
}

spearman <- function(x, y) cor(x, y, method = "spearman")

# Runs one resampling function for every measure and December and stacks the results.
run_over_grid <- function(fn) {
  pmap(grid, function(measure, date) {
    fn(get_pairs(measure, date)) |>
      mutate(measure = measure, date = date, .before = 1)
  }) |>
    list_rbind()
}

# (a) Permutation test -------------------------------------------------------
# Shuffle the outcome across countries: how often does chance give a
# correlation at least as strong as the observed one? This answers the
# question without treating the 30 countries as a random sample.
permutation_test <- function(pairs) {
  set.seed(seed)
  r_obs <- spearman(pairs$x, pairs$y)
  r_perm <- replicate(n_permutations, spearman(pairs$x, sample(pairs$y)))
  tibble(
    n_countries = nrow(pairs),
    r_obs = r_obs,
    # +1 in numerator and denominator: the observed arrangement counts as one
    # permutation, so the p-value can never be exactly zero.
    perm_p = (1 + sum(abs(r_perm) >= abs(r_obs) - 1e-12)) / (n_permutations + 1)
  )
}

# (b) Leave-one-out ------------------------------------------------------------
# Recompute the correlation dropping each country in turn: does one country
# (Czechia, Poland ...) drive the result?
leave_one_out <- function(pairs) {
  map(seq_len(nrow(pairs)), \(i) {
    tibble(
      dropped = pairs$geo[i],
      r_without = spearman(pairs$x[-i], pairs$y[-i])
    )
  }) |>
    list_rbind()
}

loo_full <- run_over_grid(leave_one_out)
loo_summary <- loo_full |>
  left_join(
    run_over_grid(\(pairs) tibble(r_obs = spearman(pairs$x, pairs$y))),
    by = c("measure", "date")
  ) |>
  group_by(measure, date) |>
  summarise(
    loo_min = min(r_without),
    loo_max = max(r_without),
    loo_most_influential = dropped[which.max(abs(r_without - r_obs))],
    .groups = "drop"
  )

# (c) Bootstrap over countries ------------------------------------------------
# Countries are resampled with replacement. Because our countries are almost
# the whole population, the interval is read as sensitivity to which countries
# are included, not as ordinary sampling error.
bootstrap_ci <- function(pairs) {
  set.seed(seed + 1)
  r_boot <- replicate(n_bootstrap, {
    rows <- sample(nrow(pairs), replace = TRUE)
    spearman(pairs$x[rows], pairs$y[rows])
  })
  tibble(
    boot_low = quantile(r_boot, 0.025, na.rm = TRUE, names = FALSE),
    boot_high = quantile(r_boot, 0.975, na.rm = TRUE, names = FALSE)
  )
}

# (d) Simulation: measurement error in the pre-war measure ---------------------
# Multiply the pre-war measure by random log-normal error of growing size and
# average the correlation over many draws. If the pre-war stock is measured
# with error, the correlation should shrink towards zero.
noise_simulation <- function(pairs) {
  set.seed(seed + 2)
  map(noise_sds, function(sd_error) {
    r_noisy <- replicate(n_noise_reps, {
      noisy_x <- pairs$x * exp(rnorm(nrow(pairs), mean = 0, sd = sd_error))
      spearman(noisy_x, pairs$y)
    })
    tibble(error_sd = sd_error, mean_r = mean(r_noisy))
  }) |>
    list_rbind()
}

# Combine and save ---------------------------------------------------------------
resampling_summary <- run_over_grid(permutation_test) |>
  left_join(run_over_grid(bootstrap_ci), by = c("measure", "date")) |>
  left_join(loo_summary, by = c("measure", "date"))
write_csv(resampling_summary, table_path("resampling_summary.csv"))
write_csv(loo_full, table_path("leave_one_out_full.csv"))

noise_results <- run_over_grid(noise_simulation)
write_csv(noise_results, table_path("noise_simulation.csv"))

# Figures ---------------------------------------------------------------------------
fig_checks <- resampling_summary |>
  mutate(year = format(date, "%Y")) |>
  ggplot(aes(year, r_obs)) +
  geom_errorbar(aes(ymin = loo_min, ymax = loo_max, colour = "leave-one-out range"),
                width = 0.15, linewidth = 1) +
  geom_pointrange(aes(ymin = boot_low, ymax = boot_high, colour = "bootstrap 95% interval"),
                  position = position_nudge(x = 0.2)) +
  geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
  facet_wrap(~measure) +
  labs(
    x = "December of", y = "Spearman correlation (observed)", colour = NULL,
    title = "How stable is the link to the pre-war community?",
    subtitle = "Point = observed correlation; bars = checks"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave(figure_path("fig_resampling_checks.png"), fig_checks, width = 9, height = 5, dpi = 150, bg = "white")

fig_noise <- noise_results |>
  mutate(year = format(date, "%Y")) |>
  ggplot(aes(error_sd, mean_r, colour = year)) +
  geom_line(linewidth = 0.8) +
  facet_wrap(~measure) +
  labs(
    x = "Size of the random error (sd on log scale)", y = "Mean Spearman correlation",
    colour = "December of",
    title = "Measurement error pulls the correlation towards zero"
  ) +
  theme_minimal()
ggsave(figure_path("fig_noise_simulation.png"), fig_noise, width = 8, height = 4.5, dpi = 150, bg = "white")
