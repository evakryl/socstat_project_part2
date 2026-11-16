# 03_descriptives.R 
#what it does: first look at the data, when each country starts reporting, totals over time and the highest per 1000 values.
#what it reads:  data/processed/panel_monthly.rds
#what it writes: reporting_overview.csv, fig_totals_over_time.png, fig_per_1000_december_2025.png
#author: Yeva (with the help of AI, more details in disclosure)

source(here::here("R", "00_config.R"))

panel <- read_rds(processed_path("panel_monthly.rds"))

#one line per country: first month with a value, months missing, months flagged. this is the "from which month does each country report" table.
reporting_overview <- panel |>
  group_by(geo) |>
  summarise(
    first_month_reported = first_observed(time, beneficiaries),
    months_missing = sum(is.na(beneficiaries)),
    months_flagged = sum(!is.na(flag)),
    flags_seen = paste(sort(unique(na.omit(flag))), collapse = " "),
    .groups = "drop"
  ) |>
  arrange(first_month_reported, geo)
write_csv(reporting_overview, table_path("reporting_overview.csv"))

#now computing the sum of what countries report. and the number of reporting countries changes over time, so the plot also shows it: a rise can be a country joining.
totals <- panel |>
  group_by(time) |>
  summarise(
    total = sum(beneficiaries, na.rm = TRUE),
    countries_reporting = sum(!is.na(beneficiaries)),
    .groups = "drop"
  )

fig_totals <- ggplot(totals, aes(time, total / 1e6)) +
  geom_line(linewidth = 0.8) +
  geom_point(aes(colour = countries_reporting), size = 1.8) +
  labs(
    x = NULL, y = "Beneficiaries, millions",
    colour = "Countries\nreporting",
    title = "People under temporary protection, sum of reported values",
    subtitle = "Published numbers, before any cleaning"
  ) +
  theme_minimal()
ggsave(figure_path("fig_totals_over_time.png"), fig_totals, width = 8, height = 4.5, dpi = 150, bg = "white")

#per 1000 inhabitants in the last December of the window.
last_december <- max(december_dates)
top_per_1000 <- panel |>
  filter(time == last_december, !is.na(per_1000)) |>
  arrange(desc(per_1000)) |>
  slice_head(n = 15)

fig_top <- ggplot(top_per_1000, aes(per_1000, reorder(geo, per_1000))) +
  geom_col() +
  labs(
    x = "Beneficiaries per 1,000 inhabitants", y = NULL,
    title = paste("Highest values,", format(last_december, "%B %Y")),
    subtitle = "Published numbers"
  ) +
  theme_minimal()
ggsave(figure_path("fig_per_1000_december_2025.png"), fig_top, width = 6, height = 5, dpi = 150, bg = "white")
