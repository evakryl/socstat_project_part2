# socstat_project_part2

**Ukrainians under temporary protection in Europe, 2022–2025**

**Course**: Social Statistics / Соціальна статистика, Final project, Part 2
**Group**: OYV
**Members**: Yeva Kryl (evakryl), Olha Oleksandrenko (olya-oleksandrenko), Victoriya Hermanchuk (vhermanchuk)

Question: **How did the geographic distribution of Ukrainians under temporary protection in Europe change from August 2022 to December 2025, and is it related to how large the Ukrainian community in each country was before the war?**

**Data**
All data come from [Eurostat](https://ec.europa.eu/eurostat/data/database), downloaded with the `eurostat` R package. the download date is in `data/raw/download_date.txt`.

**How to run**
1. unzip the folder and open project_OYV.Rproj in RStudio
2. install the packages once (the code never installs anything): here, tidyverse, eurostat, sf, rnaturalearth, rnaturalearthdata, zoo, mice.
3. in a fresh R session in the console run: source("run_all.R")
4. WORTH TO MENTION: the raw data are already in data/raw/, so no internet is needed. but in order to download the data again, set _rerun_download <- TRUE_ at the top of _run_all.R_ (needs internet). the default is FALSE. session information is saved to output/session_info.txt.

**Datasets and their usage**

1. `migr_asytpsm` | monthly beneficiaries of temporary protection, Ukrainian citizens | `migr_asytpsm.csv` |
2. `migr_pop1ctz` | Ukrainian citizens resident on 01.01.2022 (before full scale invasion) | `migr_pop1ctz.csv` |
3. `migr_resvalid` | valid residence permits held by Ukrainians, 31.12.2021 (before full scale invasion) | `migr_resvalid.csv` |
4. `demo_pjan` | total population on 1st of January `demo_pjan.csv` |

**Scripts**

0. R/00_config.R | parameters (dates, thresholds, seed, repetitions) and helper functions, loaded by every script
1. R/01_get_data.R	| eurostat (only if rerun_download)	| `data/raw/*.csv`, `download_date.txt`
2. R/02_clean.R	| data/raw/*.csv | `panel_monthly.rds`, `prewar_country.rds`
3. R/03_descriptives.R	| `panel_monthly.rds` | `reporting_overview.csv`; `fig_totals_over_time.png`, `fig_per_1000_december_2025.png`
4. R/04_missing_data.R | `panel_monthly.rds`, `panel_versions.rds`, `panel_filled_by_threshold.rds`, `panel_filled_strict.rds` | `missing_data_counts.csv`, `fig_missingness_grid.png`
5. 
