# Ukrainians under temporary protection in Europe, 2022–2025

**Course:** Social Statistics and Data Science for Economists (KSE), final project, Part 2
**Members:** Yeva Kryl (GitHub: evakryl), Olha Oleksandrenko (olya-oleksandrenko), Victoriya Hermanchuk (vhermanchuk)
**GitHub repository:** `<repo-name>` (private; instructor `dariia-m` added as collaborator)

**Question:** How did the geographic distribution of Ukrainians under temporary protection in Europe change from August 2022 to December 2025, and is it related to how large the Ukrainian community in each country was before the war?

## How to run

1. Unzip the folder and open `project_groupname.Rproj` in RStudio (R >= 4.1).
2. Install the packages once (the code never installs anything): `here`, `tidyverse` (dplyr >= 1.1, purrr >= 1.0, ggplot2 >= 3.4), `eurostat`, `sf`, `rnaturalearth`, `rnaturalearthdata`, `zoo`, `mice`.
3. In a fresh R session run: `source("run_all.R")`.

Runtime: about 5–10 minutes (most of it the imputation and the resampling in scripts 06–07; the numbers are to be updated after the first full run). Raw data are already in `data/raw/`, so no internet is needed.
To download the data again, set `rerun_download <- TRUE` at the top of `run_all.R` (needs internet; no API key). Default is `FALSE`.
All random steps use `set.seed(seed)` with `seed` defined in `R/00_config.R`. Session information is saved to `output/session_info.txt`.

## Data

All data come from [Eurostat](https://ec.europa.eu/eurostat/data/database), downloaded with the `eurostat` R package. Licence: Eurostat data may be reused with acknowledgement of the source (Commission Decision 2011/833/EU, CC BY 4.0). Raw files are in `data/raw/`, filtered to Ukrainian citizens; the download date is in `data/raw/download_date.txt`.

| Dataset | Content | Raw file |
|---|---|---|
| `migr_asytpsm` | Monthly beneficiaries of temporary protection, Ukrainian citizens | `migr_asytpsm.csv` |
| `migr_pop1ctz` | Ukrainian citizens resident on 1 Jan 2022 | `migr_pop1ctz.csv` |
| `migr_resvalid` | Valid residence permits held by Ukrainians, 31 Dec 2021 | `migr_resvalid.csv` |
| `demo_pjan` | Total population on 1 January | `demo_pjan.csv` |

Country borders: Natural Earth (public domain), via `rnaturalearth`.

## Scripts (run in this order by `run_all.R`)

| Script | Reads | Writes |
|---|---|---|
| `R/00_config.R` | – | Parameters (dates, thresholds, seed, repetitions) and helper functions; loaded by every script |
| `R/01_get_data.R` | Eurostat (only if `rerun_download`) | `data/raw/*.csv`, `download_date.txt` |
| `R/02_clean.R` | `data/raw/*.csv` | `data/processed/panel_monthly.rds`, `prewar_country.rds` |
| `R/03_descriptives.R` | `panel_monthly.rds` | `output/tables/reporting_overview.csv`, `output/figures/fig_totals_over_time.png`, `fig_per_1000_december_2025.png` |
| `R/04_missing_data.R` | `panel_monthly.rds` | `panel_versions.rds`, `panel_filled_by_threshold.rds`, `panel_filled_strict.rds`, `output/tables/missing_data_counts.csv`, `output/figures/fig_missingness_grid.png` |
| `R/05_spatial.R` | `panel_versions.rds`, `panel_filled_by_threshold.rds` | `country_distances.rds`, tables `distance_check.csv`, `centre_of_gravity.csv`, `share_change_dec_first_last.csv`; figures `fig_centre_of_gravity.png`, `fig_centre_sensitivity.png`, `fig_maps_per_1000.png` |
| `R/06_prewar_community.R` | `panel_versions.rds`, `prewar_country.rds` | `prewar_measures.rds`, `outcome_december.rds`, tables `under_reported_countries.csv`, `correlations_prewar.csv`; figures `fig_correlations_by_date.png`, `fig_scatter_prewar.png` |
| `R/07_resampling.R` | `prewar_measures.rds`, `outcome_december.rds` | tables `resampling_summary.csv`, `leave_one_out_full.csv`, `noise_simulation.csv`; figures `fig_resampling_checks.png`, `fig_noise_simulation.png` |

## Outputs and presentation slides

| Slide topic | Output |
|---|---|
| Data and coverage | `fig_totals_over_time.png`, `reporting_overview.csv` |
| Missing data: what is usable | `fig_missingness_grid.png`, `missing_data_counts.csv` |
| Where people are (maps) | `fig_maps_per_1000.png`, `fig_per_1000_december_2025.png` |
| Centre of gravity moves | `fig_centre_of_gravity.png`, `share_change_dec_first_last.csv` |
| Does it depend on our choices | `fig_centre_sensitivity.png`, `distance_check.csv` |
| Pre-war community and today | `fig_scatter_prewar.png`, `fig_correlations_by_date.png`, `under_reported_countries.csv` |
| How solid is the link | `fig_resampling_checks.png`, `fig_noise_simulation.png`, `resampling_summary.csv` |

## Limitations

All results are descriptive associations, not causal effects. A link between the pre-war Ukrainian community and the number of beneficiaries per 1,000 can also come from other factors, such as distance, labour markets or national policies, which we do not model. We have only 31 countries, so one or two countries can change a correlation noticeably. In the leave-one-out check, Czechia is the most influential country in most cases, and the correlations are lower without Poland (about 0.25–0.34 instead of 0.32–0.40). Eight countries have no published count of Ukrainian citizens on 1 January 2022: Bulgaria, Croatia, Cyprus, France, Greece, Malta, Poland and Switzerland. Together with three countries whose count looks under-reported (Slovakia, Lithuania and Hungary), their values are imputed from residence permits. The imputed citizenship measure therefore depends heavily on permits and is not an independent check. With only the 23 published values, the correlation is weaker (0.09–0.23). The permutation p-values are 0.02–0.03 for December 2022 and 0.06–0.08 for later Decembers. The bootstrap 95% intervals include zero in every case, so the link is weak and not robust. Finally, countries record temporary protection differently (flag "d" for France, Spain, Greece and Cyprus in every month). Sudden falls in the series, which look like register clean-ups, do not recover afterwards. The fall rule smooths each fall over one month but does not remove it, so part of the change in country shares may reflect administrative clean-ups rather than people moving.
