# 05_spatial.R ------------------------------------------------------------
# What it does: sub-question 1. Computes each country's distance to Kyiv (and
#               to Lviv as a check), then for every month the "centre of
#               gravity" of beneficiaries: the average distance from Ukraine,
#               each country weighted by its beneficiaries. Also maps
#               beneficiaries per 1,000 in each December and tabulates the
#               change in each country's share.
# Reads:  data/processed/panel_versions.rds,
#         data/processed/panel_filled_by_threshold.rds,
#         data/processed/panel_filled_strict.rds
# Writes: data/processed/country_distances.rds,
#         output/tables/distance_check.csv, centre_of_gravity.csv,
#         share_change_dec_first_last.csv,
#         output/figures/fig_centre_of_gravity.png, fig_centre_sensitivity.png,
#         fig_maps_per_1000.png
# Author: Olha

source(here::here("R", "00_config.R"))
library(sf)
library(rnaturalearth)

panel_versions <- read_rds(processed_path("panel_versions.rds"))
filled_by_threshold <- read_rds(processed_path("panel_filled_by_threshold.rds"))

# Country polygons --------------------------------------------------------
# Natural Earth uses ISO codes; Eurostat uses EL for Greece. iso_a2_eh is
# used because iso_a2 is "-99" for France and Norway.
world <- ne_countries(scale = "medium", returnclass = "sf")
stopifnot("iso_a2_eh" %in% names(world))
world <- world |> transmute(iso = iso_a2_eh)

eurostat_to_iso <- function(geo) if_else(geo == "EL", "GR", geo)
panel_countries <- panel_versions |>
  distinct(geo) |>
  mutate(iso = eurostat_to_iso(geo))

countries <- world |> filter(iso %in% panel_countries$iso)
not_found <- setdiff(panel_countries$iso, countries$iso)
if (length(not_found) > 0) {
  stop("No polygon for: ", paste(not_found, collapse = ", "), call. = FALSE)
}

# Distances ---------------------------------------------------------------
# A country's centre = centroid of its largest polygon, so that overseas
# territories (French Guiana, Svalbard ...) do not pull it away. Centroids are
# computed in a projected CRS (EPSG:3035, metres) and converted back to
# lon/lat (EPSG:4326); distances are then geodesic, in km.
largest_part_centroids <- function(countries_sf) {
  parts <- countries_sf |>
    st_cast("MULTIPOLYGON", warn = FALSE) |>
    st_cast("POLYGON", warn = FALSE) |>
    mutate(area = as.numeric(st_area(geometry)))
  largest <- parts |>
    group_by(iso) |>
    slice_max(area, n = 1, with_ties = FALSE) |>
    ungroup()
  # The only attribute (iso) is constant within each polygon: saying so
  # silences sf's "attributes are constant over geometries" warning honestly.
  st_agr(largest) <- "constant"
  largest |>
    st_transform(3035) |>
    st_centroid() |>
    st_transform(4326)
}
centres <- largest_part_centroids(countries)
stopifnot(st_crs(centres) == st_crs(4326))

kyiv_sf <- st_sfc(st_point(unname(kyiv)), crs = 4326)
lviv_sf <- st_sfc(st_point(unname(lviv)), crs = 4326)

country_distances <- centres |>
  st_drop_geometry() |>
  select(iso) |>
  mutate(
    dist_kyiv_km = as.numeric(st_distance(centres, kyiv_sf)) / 1000,
    dist_lviv_km = as.numeric(st_distance(centres, lviv_sf)) / 1000
  ) |>
  right_join(panel_countries, by = "iso")
stopifnot(nrow(country_distances) == nrow(panel_countries))
write_rds(country_distances, processed_path("country_distances.rds"))

# Robustness: do the two reference points order the countries alike?
distance_check <- tibble(
  spearman_kyiv_vs_lviv = cor(
    country_distances$dist_kyiv_km, country_distances$dist_lviv_km,
    method = "spearman"
  )
)
write_csv(distance_check, table_path("distance_check.csv"))

# Centre of gravity ---------------------------------------------------------
# weighted.mean over the countries that have a value in that month. The number
# of countries is kept, because a country joining or leaving moves the average.
centre_of_gravity <- function(df, distance_col = "dist_kyiv_km") {
  df |>
    filter(!is.na(beneficiaries)) |>
    left_join(country_distances, by = "geo") |>
    group_by(across(any_of(c("version", "threshold"))), time) |>
    summarise(
      centre_km = weighted.mean(.data[[distance_col]], beneficiaries),
      countries = n(),
      .groups = "drop"
    )
}

# Countries with a value in every month of the filled version: a fixed set,
# so the average cannot move just because the set of countries changed.
balanced_countries <- panel_versions |>
  filter(version == "filled") |>
  group_by(geo) |>
  filter(!any(is.na(beneficiaries))) |>
  ungroup() |>
  distinct(geo) |>
  pull(geo)

centre_versions <- bind_rows(
  centre_of_gravity(panel_versions),
  centre_of_gravity(
    panel_versions |> filter(version == "filled", geo %in% balanced_countries)
  ) |>
    mutate(version = "filled, balanced countries")
)
write_csv(centre_versions, table_path("centre_of_gravity.csv"))

fig_centre <- ggplot(centre_versions, aes(time, centre_km, colour = version)) +
  geom_line(linewidth = 0.8) +
  labs(
    x = NULL, y = "Average distance from Kyiv, km", colour = NULL,
    title = "Centre of gravity of beneficiaries",
    subtitle = "Three versions of the monthly series, plus a fixed set of countries"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave(figure_path("fig_centre_of_gravity.png"), fig_centre, width = 8, height = 5, dpi = 150)

# Sensitivity: other fall thresholds, and Lviv instead of Kyiv.
centre_sensitivity <- bind_rows(
  filled_by_threshold |>
    rename(beneficiaries = filled) |>
    centre_of_gravity() |>
    mutate(reference = "Kyiv", series = paste0("fall threshold ", threshold * 100, "%")),
  panel_versions |>
    filter(version == "filled") |>
    centre_of_gravity("dist_lviv_km") |>
    mutate(reference = "Lviv", series = "Lviv as reference point"),
  read_rds(processed_path("panel_filled_strict.rds")) |>
    rename(beneficiaries = filled) |>
    centre_of_gravity() |>
    mutate(reference = "Kyiv", series = "also excluding flag d")
)
fig_sensitivity <- ggplot(centre_sensitivity, aes(time, centre_km, colour = series)) +
  geom_line(linewidth = 0.8) +
  labs(
    x = NULL, y = "Average distance, km", colour = NULL,
    title = "Does the pattern depend on our choices?",
    subtitle = "Filled version, other thresholds, and Lviv as reference"
  ) +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave(figure_path("fig_centre_sensitivity.png"), fig_sensitivity, width = 8, height = 5, dpi = 150)

# Change in each country's share between the first and last December --------
first_dec <- min(december_dates)
last_dec <- max(december_dates)
share_change <- panel_versions |>
  filter(version == "filled", time %in% c(first_dec, last_dec)) |>
  select(geo, time, beneficiaries) |>
  pivot_wider(names_from = time, values_from = beneficiaries) |>
  drop_na() |>
  mutate(
    share_first = .data[[as.character(first_dec)]] / sum(.data[[as.character(first_dec)]]),
    share_last = .data[[as.character(last_dec)]] / sum(.data[[as.character(last_dec)]]),
    change_pp = (share_last - share_first) * 100
  ) |>
  arrange(desc(change_pp))
write_csv(share_change, table_path("share_change_dec_first_last.csv"))

# Maps ----------------------------------------------------------------------
# Beneficiaries per 1,000 in each December (filled version). Each polygon is
# repeated once per December, so we check the number of rows after the join.
dec_values <- panel_versions |>
  filter(version == "filled", time %in% december_dates) |>
  mutate(
    iso = eurostat_to_iso(geo),
    month_label = factor(format(time, "%B %Y"),
                         levels = format(sort(december_dates), "%B %Y"))
  ) |>
  select(iso, month_label, per_1000)

map_data <- left_join(countries, dec_values, by = "iso")
stopifnot(nrow(map_data) == nrow(countries) * length(december_dates))

fig_maps <- ggplot() +
  geom_sf(data = world, fill = "grey95", colour = "white", linewidth = 0.1) +
  geom_sf(data = map_data, aes(fill = per_1000), colour = "white", linewidth = 0.1) +
  geom_sf(data = st_sf(geometry = kyiv_sf), shape = 8, size = 2) +
  facet_wrap(~month_label) +
  # Binned colours: a few countries (Czechia, Poland) are far above the rest,
  # and bins keep the other countries distinguishable.
  scale_fill_viridis_b(na.value = "grey80", name = "Per 1,000") +
  coord_sf(xlim = europe_xlim, ylim = europe_ylim) +
  labs(
    title = "Beneficiaries of temporary protection per 1,000 inhabitants",
    subtitle = "Filled version; grey = no usable value; star = Kyiv"
  ) +
  theme_minimal()
ggsave(figure_path("fig_maps_per_1000.png"), fig_maps, width = 10, height = 8, dpi = 150)
