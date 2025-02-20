#### Corona-Script SWITZERLAND (automated version) #### 

#prep
rm(list=ls(all=TRUE)) # Alles bisherige im Arbeitssprecher loeschen
options(scipen=999)
library(tidyverse)
library(jsonlite)
library(zoo)

# import helper functions
source("./helpers.R")

# read in additional data
pop <- read_csv("./corona-auto-ch/pop_kant.csv")

#### Update R eth estimate ####

eth <- read_csv("https://raw.githubusercontent.com/covid-19-Re/dailyRe-Data/master/CHE-estimates.csv") %>%
  filter(region == "CHE" & 
           data_type == "Confirmed cases" & 
           estimate_type == "Cori_slidingWindow") %>%
  add_row(date = Sys.Date()-1) %>%
  select(date, median_R_highHPD,median_R_lowHPD,median_R_mean) %>%
  filter(date > "2020-03-02")


eth_notes <- paste0("* 95%-Konfidenzintervall. Die Schätzung endet am ", format(nth(eth$date, -2), format = "%d. %m. %Y"),".")
eth_title <- case_when(nth(eth$median_R_mean, -2) < 0.7 ~ "Die Reproduktionszahl liegt deutlich unter 1",
                       nth(eth$median_R_mean, -2) > 0.7 & nth(eth$median_R_mean, -2) < 0.9 ~ "Die Reproduktionszahl liegt unter 1",
                       nth(eth$median_R_mean, -2) > 0.9 & nth(eth$median_R_mean, -2) < 1.1  ~ "Die Reproduktionszahl liegt etwa bei 1",
                       nth(eth$median_R_mean, -2) > 1.1 & nth(eth$median_R_mean, -2) < 1.3  ~ "Die Reproduktionszahl liegt über 1",
                       nth(eth$median_R_mean, -2) > 1.3 ~ "Die Reproduktionszahl liegt deutlich über 1")

colnames(eth) <- c("Datum", "", "Unsicherheitsbereich*", "Median")

#q-cli update
update_chart(id = "d84021d6716b1e848bd91a20e2b63cb0", 
             data = eth, 
             notes = eth_notes,
             title = eth_title)

#### Update R eth estimate cantons ####

## 10 biggest: ZH, BE, VD, AG, SG, GE, LU, TI, VS, FR

eth_cantons <- read_csv("https://raw.githubusercontent.com/covid-19-Re/dailyRe-Data/master/CHE-estimates.csv") %>%
  filter(region %in% c("BE","ZH","VD","AG","SG","GE","LU", "TI","VS", "FR")) %>%
  filter(data_type == "Confirmed cases" & estimate_type == "Cori_slidingWindow") %>%
  group_by(region) %>%
  filter(date == last(date)) %>%
  ungroup() %>%
  left_join(pop[,1:2], by = c("region" = "ktabk")) %>%
  select(kt, median_R_highHPD,median_R_lowHPD,median_R_mean) %>%
  arrange(desc(median_R_mean))

eth_cantons_title <- paste0("Der Kanton ", eth_cantons[1,1], " verzeichnet den höchsten R-Wert")
eth_cantons_notes <- paste0("Die Daten liegen in einem 95%-Konfidenzintervall. Wir zeigen nur die R-Werte für die zehn grössten Kantone.",
                            " In kleinen Kantonen ist der Unsicherheitsbereich teilweise sehr gross, so dass keine verlässlichen Aussagen möglich sind.",
                            " Die neusten Schätzungen der Kantone liegen in der Regel einige Tage hinter der nationalen Schätzung.<br> Stand: ",
                            format(nth(eth$Datum, -2)-4, format = "%d. %m. %Y"))

colnames(eth_cantons) <- c("Kanton", "", "Unsicherheitsbereich", "Median")

#q-cli update
update_chart(id = "f649302cbf7dd462f339d0cc35d9695a", 
             data = eth_cantons, 
             notes = eth_cantons_notes,
             title = eth_cantons_title)

#### Update BAG data ####

# data gathering

bag_data <- fromJSON('https://www.covid19.admin.ch/api/data/context')

bag_cases <- read_csv(bag_data$sources$individual$csv$daily$cases)%>% 
  select("geoRegion", "datum", "entries", "sumTotal", "pop") %>%
  filter(datum != max(datum)) #exclude today, because new cases will not be there

bag_cases_age <- read_csv(bag_data$sources$individual$csv$weekly$byAge$cases) %>%
  select("altersklasse_covid19", "geoRegion", "datum", "entries", "sumTotal")

bag_deaths <- read_csv(bag_data$sources$individual$csv$daily$death) %>%
  select("geoRegion", "datum", "entries", "sumTotal") %>%
  filter(datum != max(datum)) #exclude today

bag_hosps <- read_csv(bag_data$sources$individual$csv$daily$hosp) %>%
  select("geoRegion", "datum", "entries", "sumTotal") %>%
  filter(datum != max(datum)) #exclude today

bag_hosp_cap <- read_csv(bag_data$sources$individual$csv$daily$hospCapacity) %>%
  select("geoRegion", "date", "ICUPercent_AllPatients", "ICUPercent_NonCovid19Patients",
         "ICUPercent_Covid19Patients", "ICUPercent_FreeCapacity", 
         "TotalPercent_AllPatients", "TotalPercent_NonCovid19Patients", 
         "TotalPercent_Covid19Patients", "TotalPercent_FreeCapacity") %>%
  filter(date != max(date)) #exclude today

bag_tests <- read_csv(bag_data$sources$individual$csv$daily$test) %>%
  select("geoRegion", "datum", "entries", "pos_anteil", "sumTotal", "pop")

bag_testPcrAntigen <- read_csv(bag_data$sources$individual$csv$daily$testPcrAntigen) %>% 
  select("geoRegion", "datum", "entries", "nachweismethode", "pos_anteil")


# Total cases in CH since 2020-02-24 and recovery calculation

bag_total <- merge(bag_cases, bag_deaths, by = c("geoRegion", "datum")) %>%
  filter(geoRegion == 'CHFL') %>%
  mutate(Infizierte = sumTotal.x -sumTotal.y) %>%
  rename("Tote" = `sumTotal.y`) %>%
  select(datum, Infizierte, Tote) %>%
  mutate(`Genesene (Schätzung)` = ((lag(Infizierte,14, default = 0)) * 0.75) + 
           ((lag(Infizierte ,21, default = 0)) * 0.10) + 
           ((lag(Infizierte,28, default = 0)) * 0.10) +
           ((lag(Infizierte,42, default = 0)) * 0.05)) %>%
  mutate(`gegenwärtig Infizierte` = Infizierte-`Genesene (Schätzung)`) %>%
  select("datum", "Tote", "gegenwärtig Infizierte", "Genesene (Schätzung)")

bag_total_title <- paste0("Über ",str_sub(sum(tail(bag_total[,2:4], 1),3),1,3), " 000 bestätigte Infektionen in der Schweiz")

#q-cli update
update_chart(id = "3209a77a596162b06346995b10896863", 
             data = bag_total, 
             title = bag_total_title)


#Rolling average of cases
bag_cases_ravg <- bag_cases %>%
  filter(geoRegion == 'CHFL', datum <= last(datum)-2) %>%
  mutate(ravg_cases = round(rollmean(entries, 7, fill = 0, align = "right"),0)) %>%
  select(datum, ravg_cases) 

#q-cli update
update_chart(id = "93b53396ee7f90b1271f620a0472c112", data = bag_cases_ravg)

# Tests (Antigen and PCR), absolute number

bag_testPcrAntigen_abs <- bag_testPcrAntigen %>% 
  filter(datum > "2020-11-01", geoRegion == 'CHFL') %>%
  select(datum, entries, nachweismethode) %>%
  spread(nachweismethode, entries) %>%
  mutate("Antigen-Schnelltest" = round(rollmean(Antigen_Schnelltest, 7, fill = 0, align = "right"), 1), 
         "PCR-Test" = round(rollmean(PCR, 7, na.pad = TRUE, align = "right"), 1)) %>%
  select(datum, `Antigen-Schnelltest`, `PCR-Test`) %>%
  filter(`Antigen-Schnelltest` + `PCR-Test` > 0) %>%
  drop_na() 

#q-cli update
update_chart(id = "fe58121b9eb9cbc28fb71b8810a7b573", data = bag_testPcrAntigen_abs)


# Positivity rate (PCR and Antigen)
bag_tests_pct <- bag_testPcrAntigen %>%
  filter(datum > "2020-11-01", geoRegion == 'CHFL') %>%
  group_by(nachweismethode) %>%
  mutate(pct = round(rollmean(pos_anteil, 7, na.pad = TRUE, align = "right"), 1)) %>%
  select(nachweismethode, datum, pct) %>%
  spread(nachweismethode, pct) %>%
  drop_na()  %>%
  rename("Antigen-Schnelltest" = Antigen_Schnelltest, "PCR-Test" = PCR) %>%
  add_column("WHO-Zielwert" = 5)

#q-cli update
update_chart(id = "e18ed50b4fad7ada8063e3a908eb77ac", data = bag_tests_pct)

# Age distribution of cases, weekly
bag_age  <- bag_cases_age %>%
  filter(!is.na(datum), altersklasse_covid19 != "Unbekannt", geoRegion == "CHFL") %>%
  mutate(datum = paste0(substr(datum, 1, 4), "-W", substr(datum, 5, 6))) %>%
  select(datum, altersklasse_covid19, entries) %>%
  spread(altersklasse_covid19, entries) %>%
  mutate(`0-19` = `0 - 9` +  `10 - 19`,
         `20-39` = `20 - 29` +  `30 - 39`,
         `40-59` = `40 - 49` +  `50 - 59`,
         `60-79` = `60 - 69` +  `70 - 79`) %>%
  select(datum, `0-19`,`20-39`, `40-59`, `60-79`, `80+`) %>%
  slice(1:n()-1) #incomplete week results, can be removed by Wednesday

# make relative values 
bag_age[2:6] <- bag_age[2:6]/rowSums(bag_age[2:6])*100

#q-cli update
update_chart(id = "cbef3c928fa4c500c77a2a561e724af6", data = bag_age)


# Kantone 14 Tage Choropleth
bag_kanton_choro <- bag_cases %>%
  filter(!is.na(datum), datum >= max(datum)-13, geoRegion != "CHFL", geoRegion != "CH", geoRegion != "FL") %>%
  group_by(geoRegion, pop) %>%
  summarise(sum = sum(entries), .groups = "drop") %>%
  mutate(per100k = round(100000*sum/pop, 0)) %>%
  arrange(geoRegion) %>%
  select(geoRegion, per100k)

bag_kanton_choro_notes <- paste0("Stand: ", format(max(bag_cases$datum), , format = "%d. %m. %Y"))

update_chart(id = "a2fc71a532ec45c64434712991efb41f", data = bag_kanton_choro, notes = bag_kanton_choro_notes)


### Hospitalisierungen und Todesfälle

# Absolut 
roll_ch_bag_death_hosp <- bag_cases %>%
  full_join(bag_deaths, by = c("geoRegion", "datum")) %>%
  full_join(bag_hosps, by = c("geoRegion", "datum")) %>%
  filter(datum >= "2020-02-28" & datum <=  last(datum)-2, geoRegion == 'CHFL')  %>%
  mutate(entries.y = replace_na(entries.y, 0),
         hosp_roll = rollmean(entries,7,fill = 0, align = "right"),
         death_roll = rollmean(entries.y,7,fill = 0, align = "right")) %>%
  select(datum, hosp_roll, death_roll) %>%
  rename(Hospitalierungen = hosp_roll, Todesfälle = death_roll)

update_chart(id = "2e86418698ad77f1247bedf99b771e99", data = roll_ch_bag_death_hosp)


# Todesfälle und Hospitalisierungen absolut nach Altersklasse 

bag_deaths_age <- read_csv(bag_data$sources$individual$csv$weekly$byAge$death) %>%
  select("altersklasse_covid19", "geoRegion", "datum", "entries", "sumTotal") %>%
  mutate(KW = substr(datum, 5, 6), year = substr(datum, 1, 4))

bag_hosp_age <- read_csv(bag_data$sources$individual$csv$weekly$byAge$hosp) %>%
  select("altersklasse_covid19", "geoRegion", "datum", "entries", "sumTotal")  %>%
  mutate(KW = substr(datum, 5, 6), year = substr(datum, 1, 4))

bag_age_deaths  <- bag_deaths_age %>%
  filter(!is.na(datum), altersklasse_covid19 != "Unbekannt", geoRegion == 'CHFL', (year >= '2021' | (year == '2020' & KW >= '52' ) )) %>%
  mutate(datum = paste0(year, "-W", KW)) %>%
  select(datum, altersklasse_covid19, entries) %>%
  spread(altersklasse_covid19, entries) %>%
  mutate(`0–59` = `0 - 9` +  `10 - 19` + `20 - 29` +  `30 - 39` + `40 - 49` +  `50 - 59`, `60–79` = `60 - 69` +  `70 - 79`) %>%
  select(datum, `0–59`,`60–79`, `80+`) %>%
  slice(1:n()-1) #incomplete week results

update_chart(id = "ec163329f1a1a5698ef5d1ee7587b3d6", data = bag_age_deaths)


bag_age_hosps  <- bag_hosp_age %>%
  filter(!is.na(datum), altersklasse_covid19 != "Unbekannt", geoRegion == 'CHFL', (year >= '2021' | (year == '2020' & KW >= '52' ) )) %>%
  mutate(datum = paste0(year, "-W", KW)) %>%
  select(datum, altersklasse_covid19, entries) %>%
  spread(altersklasse_covid19, entries) %>%
  mutate(`0–59` = `0 - 9` +  `10 - 19` + `20 - 29` +  `30 - 39` + `40 - 49` +  `50 - 59`, `60–79` = `60 - 69` +  `70 - 79`) %>%
  select(datum, `0–59`,`60–79`, `80+`) %>%
  slice(1:n()-1) #incomplete week results

update_chart(id = "b3423b05ea50c39f8da718719ec3d161", data = bag_age_hosps)

### Intensivbetten 

bag_hosp_cap <- subset(read_csv(bag_data$sources$individual$csv$daily$hospCapacity), type_variant == 'fp7d',
                       select = c("geoRegion", "date", "ICU_AllPatients", "ICU_Covid19Patients", "ICU_Capacity",
                                  "ICUPercent_AllPatients", "ICUPercent_NonCovid19Patients", "ICUPercent_Covid19Patients",
                                  "ICUPercent_FreeCapacity")) %>%
  mutate("Freie Betten" = ICU_Capacity - ICU_AllPatients, "Andere Patienten" = ICU_AllPatients - ICU_Covid19Patients)


names(bag_hosp_cap) <- c('geoRegion', 'datum', "Auslastung", 
                         "Patienten mit Covid-19", "Kapazität",
                         "Auslastung in %", 
                         "Andere Patienten in %", "Patienten mit Covid-19 in %",
                         "Freie Betten in %", "Freie Betten", "Andere Patienten")

bag_hosp_cap_ch <- subset(bag_hosp_cap, geoRegion == 'CH', select = c('datum', 'Patienten mit Covid-19', 'Andere Patienten', 'Freie Betten')) 


update_chart(id = "bd30a27068812f7ec2474f10e427300c", data = bag_hosp_cap_ch)


bag_hosp_cap_cantons <- subset(bag_hosp_cap, datum == max(datum) & geoRegion != 'CHFL' & geoRegion != 'CH' & geoRegion != 'FL', select = c('geoRegion', 'Auslastung', 'Kapazität', 'Patienten mit Covid-19', 'Andere Patienten', 'Freie Betten'))

bag_hosp_cap_cantons$region <- ""
bag_hosp_cap_cantons[bag_hosp_cap_cantons$geoRegion == 'GE' | 
                       bag_hosp_cap_cantons$geoRegion == 'VS' |
                       bag_hosp_cap_cantons$geoRegion == 'VD'
                     , "region"] <- "Genferseeregion"
bag_hosp_cap_cantons[bag_hosp_cap_cantons$geoRegion == 'BE' | 
                       bag_hosp_cap_cantons$geoRegion == 'SO' |
                       bag_hosp_cap_cantons$geoRegion == 'FR' |
                       bag_hosp_cap_cantons$geoRegion == 'NE' |
                       bag_hosp_cap_cantons$geoRegion == 'JU'
                     , "region"] <- "Espace Mittelland"
bag_hosp_cap_cantons[bag_hosp_cap_cantons$geoRegion == 'BS' | 
                       bag_hosp_cap_cantons$geoRegion == 'BL' |
                       bag_hosp_cap_cantons$geoRegion == 'AG' 
                     , "region"] <- "Nordwestschweiz"
bag_hosp_cap_cantons[bag_hosp_cap_cantons$geoRegion == 'ZH'  
                     , "region"] <- "Zürich"
bag_hosp_cap_cantons[bag_hosp_cap_cantons$geoRegion == 'SG' | 
                       bag_hosp_cap_cantons$geoRegion == 'TG' |
                       bag_hosp_cap_cantons$geoRegion == 'AI' | 
                       bag_hosp_cap_cantons$geoRegion == 'AR' | 
                       bag_hosp_cap_cantons$geoRegion == 'GL' |
                       bag_hosp_cap_cantons$geoRegion == 'GR' |
                       bag_hosp_cap_cantons$geoRegion == 'SH'
                     , "region"] <- "Ostschweiz"
bag_hosp_cap_cantons[bag_hosp_cap_cantons$geoRegion == 'TI'  
                     , "region"] <- "Tessin"
bag_hosp_cap_cantons[bag_hosp_cap_cantons$geoRegion == 'LU' | 
                       bag_hosp_cap_cantons$geoRegion == 'UR' |
                       bag_hosp_cap_cantons$geoRegion == 'SZ' |
                       bag_hosp_cap_cantons$geoRegion == 'OW' |
                       bag_hosp_cap_cantons$geoRegion == 'NW' |
                       bag_hosp_cap_cantons$geoRegion == 'ZG' 
                     , "region"] <- "Zentralschweiz"


bag_hosp_cap_regions <- bag_hosp_cap_cantons %>%
  group_by(region) %>% 
  drop_na()  %>%
  summarise(Auslastung = sum(Auslastung),
            "Kapazität" = sum(`Kapazität`),
            "Patienten mit Covid-19" = sum(`Patienten mit Covid-19`),
            "Andere Patienten" = sum(`Andere Patienten`),
            "Freie Betten" = sum(`Freie Betten`)) %>% 
  mutate("Patienten mit Covid-19" = `Patienten mit Covid-19`*100/`Kapazität`,
    "Andere Patienten" = `Andere Patienten`*100/`Kapazität`,
    "Freie Betten" = `Freie Betten`*100/`Kapazität`) %>%
  select(1, 4:6) %>%
  arrange(desc(`Patienten mit Covid-19`))

# percentages for notes
bag_hosp_cap_regions_notes <- paste0("Schweizweit sind derzeit etwa ", 
                                      last(subset(bag_hosp_cap, geoRegion == 'CH', select = c('datum', 'Auslastung in %'))$'Auslastung in %' ), 
                                      " Prozent der Intensivbetten belegt. Die Covid-19-Patienten machen derzeit rund ", 
                                      round(100*last(subset(bag_hosp_cap, geoRegion == 'CH', select = c('datum', 'Patienten mit Covid-19'))$'Patienten mit Covid-19') / 
                                              last(subset(bag_hosp_cap, geoRegion == 'CH', select = c('datum', 'Auslastung'))$'Auslastung')),
                                      " Prozent der Patienten aus.<br>Stand: ",
                                     format(max(bag_hosp_cap$datum), format = "%d. %m. %Y"))


update_chart(id = "e7ab74f261f39c7b670954aaed6de280", data = bag_hosp_cap_regions, notes = bag_hosp_cap_regions_notes)

#### Bezirke Cases ####

bag_cases_bez <- read_csv(bag_data$sources$individual$csv$extraGeoUnits$cases$biweekly) %>%
  select("geoRegion", "period_end_date", "inzCategoryNormalized") %>%
  filter(period_end_date == max(period_end_date)) %>%
  filter(grepl('BZRK', geoRegion)) %>%
  mutate(geoRegion = as.numeric(str_sub(geoRegion,5,9))) %>%
  select(-period_end_date) %>%
  arrange(geoRegion)

bag_cases_bez_dates <- read_csv(bag_data$sources$individual$csv$extraGeoUnits$cases$biweekly) %>%
  filter(period_end_date == max(period_end_date), geoRegion == "CH") %>%
  select(period_start_date, period_end_date)

bag_cases_bez_notes <- paste0("Zeitraum: ", 
                              format(bag_cases_bez_dates$period_start_date, format = "%d. %m."),
                              " bis ",
                              format(bag_cases_bez_dates$period_end_date, format = "%d. %m. %Y"),
                              ". Die Zahlen werden alle 2 Wochen aktualisiert.")

update_chart(id = "e7ab74f261f39c7b670954aaed6de280", data = bag_hosp_cap_regions, notes = bag_hosp_cap_regions_notes)


#### CH Vaccinations ####
# update on TUE and FRI, check if new BAG vacc data are there, if not read in again later

#get latest bag figures
ch_vacc_del <- read_csv(bag_data$sources$individual$csv$vaccDosesDelivered) %>% 
  filter(type == "COVID19VaccDosesDelivered") %>%
  select(geoRegion, date,pop, sumTotal) %>%
  drop_na()

ch_vacc_adm <- read_csv(bag_data$sources$individual$csv$vaccDosesAdministered) %>% 
  select(geoRegion, date, sumTotal, per100PersonsTotal) %>%
  drop_na()

ch_vacc_full <- read_csv(bag_data$sources$individual$csv$vaccPersons) %>%
  filter(type == "COVID19FullyVaccPersons") %>%
  select(geoRegion, date, sumTotal) %>%
  drop_na()

ch_vacc_rec <- read_csv(bag_data$sources$individual$csv$vaccDosesDelivered) %>% 
  filter(type == "COVID19VaccDosesReceived") %>%
  select(geoRegion, date,pop, sumTotal) %>%
  drop_na()

ch_vacc_date <- format(last(ch_vacc_adm$date), format = "%d. %m. %Y") #which is the last date available?

ch_vacc <- ch_vacc_adm %>%
  full_join(ch_vacc_del, by = c("geoRegion", "date")) %>%
  full_join(ch_vacc_full, by = c("geoRegion", "date")) %>%
  select(geoRegion, date, pop, sumTotal.y, sumTotal.x, sumTotal, per100PersonsTotal)%>%
  rename(geounit = geoRegion, 
         ncumul_delivered_doses = sumTotal.y, 
         ncumul_vacc_doses = sumTotal.x, 
         ncumul_fully_vacc = sumTotal) %>%
  group_by(geounit) %>%
  mutate(new_vacc_doses = ncumul_vacc_doses-lag(ncumul_vacc_doses))%>%
  mutate(ncumul_firstdoses_vacc = ncumul_vacc_doses - ncumul_fully_vacc) %>%
  mutate(ncumul_onlyfirstdoses_vacc = ncumul_firstdoses_vacc - ncumul_fully_vacc) %>%
  full_join(pop[,c(1,2)], by = c("geounit" = "ktabk")) %>%
  fill(pop, ncumul_delivered_doses) %>%
  ungroup()

# Charts Vaccinations
vacc_pop <- ch_vacc %>%
  mutate(ncumul_notvacc_doses = ncumul_delivered_doses - ncumul_vacc_doses) %>%
  mutate(pct_vacc_doses = ncumul_vacc_doses*100/pop) %>%
  mutate(pct_delivered_doses = ncumul_delivered_doses*100/pop) %>%
  mutate(pct_notvacc_doses = pct_delivered_doses - pct_vacc_doses) %>%
  mutate(verimpft = ncumul_vacc_doses*100/ncumul_delivered_doses) %>%
  mutate("nicht verimpft" = ncumul_notvacc_doses*100/ncumul_delivered_doses)


## Ich habe die folgende Karte aus dem Grafikstück genommen, da sie sich mit einer anderen Grafik doppelt.
## Muss aber trotzdem aktualisiert werden für Newsroom (fsl)

vaccchart_kant <-vacc_pop %>%
  filter(geounit != "FL" & geounit != "CHFL"  & geounit != "CH") %>%
  group_by(geounit) %>%
  filter(date ==last(date)) %>%
  ungroup() %>%
  select(geounit, pct_vacc_doses) %>%
  mutate(pct_vacc_doses = round(pct_vacc_doses, 1)) %>%
  arrange(geounit)

vaccchart_kant_notes <- paste0("Die Zahlen beziehen sich auf die verabreichten Impfdosen, nicht auf geimpfte Personen.",
                               " Eine Person muss im Normalfall zwei Dosen verimpft bekommen.<br> Stand: ", 
                               ch_vacc_date)

update_chart(id = "e039a1c64b33e327ecbbd17543e518d3", data = vaccchart_kant, notes = vaccchart_kant_notes)


vaccchart_pctfull <- vacc_pop %>%
  filter(geounit != "FL" & geounit != "CHFL"  & geounit != "CH") %>%
  group_by(geounit) %>%
  filter(date ==last(date)) %>%
  ungroup() %>%
  select(kt, verimpft, "nicht verimpft") %>%
  arrange(desc(verimpft))

vaccchart_pctfull$`nicht verimpft`[vaccchart_pctfull$`nicht verimpft` < 0] <- NA

vaccchart_pctfull_notes <- paste0("In einigen Kantonen wurden mehr Impfdosen aus den Ampullen gewonnen,",
                                  " als offiziell in den Lieferangaben ausgewiesen ist.<br>Stand: ",
                                  ch_vacc_date)

update_chart(id = "f8559c7bb8bfc74e70234e717e0e1f8e", 
             data = vaccchart_pctfull, 
             notes = vaccchart_pctfull_notes)


vaccchart_pctpop <- vacc_pop %>%
  filter(geounit != "FL" & geounit != "CHFL"  & geounit != "CH") %>%
  group_by(geounit) %>%
  filter(date ==last(date)) %>%
  ungroup() %>%
  select(kt, pct_vacc_doses, pct_notvacc_doses) %>%
  rename("Verimpft" = pct_vacc_doses, "Nicht verimpft" = pct_notvacc_doses)

vaccchart_pctpop$`Nicht verimpft`[vaccchart_pctpop$`Nicht verimpft` < 0] <- 0

vaccchart_pctpop2 <- vaccchart_pctpop %>%
  mutate(bar = Verimpft+`Nicht verimpft`) %>%
  arrange(desc(bar)) %>%
  select(-bar)

update_chart(id = "5e2bb3f16c0802559ccdf474af11f453", 
             data = vaccchart_pctpop, 
             notes = paste0("Stand: ", ch_vacc_date))

# second doses
vacc_ch_2nd <- ch_vacc %>%
  select(geounit, kt, date, pop, ncumul_fully_vacc, ncumul_onlyfirstdoses_vacc) %>%
  drop_na(ncumul_fully_vacc) %>%
  filter(geounit != "CH" & geounit != "FL" & geounit != "CHFL" & date == last(date)) %>%
  mutate(first_pct = ncumul_onlyfirstdoses_vacc*100/pop,
         second_pct = ncumul_fully_vacc*100/pop) %>%
  select(kt, second_pct, first_pct) %>%
  arrange(desc(second_pct)) %>%
  rename("Vollständig geimpft" = second_pct, "Nur erste Dosis erhalten" = first_pct)

update_chart(id = "54381c24b03b4bb9d1017bb91511e21d", 
             data = vacc_ch_2nd, 
             notes = paste0("Stand: ", ch_vacc_date))

### Schweiz geimpft nach Altersgruppen

vacc_ch_age <- read_csv(bag_data$sources$individual$csv$weeklyVacc$byAge$vaccPersons) %>%
  filter(geoRegion == 'CHFL', type == "COVID19FullyVaccPersons") %>%
  filter(date ==last(date)) %>%
  select(altersklasse_covid19, per100PersonsTotal) %>%
  rename('Altersklasse' = altersklasse_covid19, "Vollständig geimpfte Personen" = per100PersonsTotal) %>%
  filter(`Vollständig geimpfte Personen` > 1) %>%
  mutate(`Vollständig geimpfte Personen` = round(`Vollständig geimpfte Personen`, 1)) %>%
  arrange(desc(`Vollständig geimpfte Personen`))

update_chart(id = "674ce1e7cf4282ae2db76136cb301ba1", 
             data = vacc_ch_age, 
             notes = paste0("Stand: ", ch_vacc_date))

#### Vaccination, delivered, received ####

ch_vacc_missing_dates <- seq(as.Date("2020-12-23"), as.Date("2021-01-24"), by = "days") %>% as_tibble()

ch_vacc_vdr <- ch_vacc %>%
  filter(geounit == "CHFL") %>%
  select(date, ncumul_vacc_doses, ncumul_delivered_doses) %>%
  full_join(ch_vacc_rec[,c(2,4)], by = "date") %>%
  rename(ncumul_rec_doses = sumTotal) %>%
  add_row(date = as.Date("2020-12-23"), ncumul_vacc_doses = 0, .before = 1) %>%
  add_row(date = as.Date("2021-01-14"), ncumul_vacc_doses = 66000, .after = 1) %>%
  add_row(date = as.Date("2021-01-19"), ncumul_vacc_doses = 110000, .after = 2) %>%
  rename(Verimpft = ncumul_vacc_doses) %>%
  mutate("An Kantone verteilt" = ncumul_delivered_doses-Verimpft,
         "in die Schweiz geliefert" = ncumul_rec_doses-ncumul_delivered_doses) %>%
  select(-c(3:4))

ch_vacc_vdr$`An Kantone verteilt`[ch_vacc_vdr$`An Kantone verteilt`< 0] <- 0
tail(ch_vacc_vdr,1)

update_chart(id = "ce1529d1facf24bb5bef83a3df033bfc", 
             data = ch_vacc_vdr)


#### Vaccination Projection CH ####
ch_vacc_proj <- ch_vacc %>%
  filter(geounit == "CHFL") %>%
  select(date, ncumul_vacc_doses) %>%
  add_row(date = as.Date("2020-12-23"), ncumul_vacc_doses = 0, .before = 1) %>%
  add_row(date = as.Date("2021-01-14"), ncumul_vacc_doses = 66000, .after = 1) %>%
  add_row(date = as.Date("2021-01-19"), ncumul_vacc_doses = 110000, .after = 2) %>%
  full_join(ch_vacc_missing_dates, by = c("date" = "value")) %>% arrange(date) %>%
  mutate(ncumul_vacc_doses = na.approx(ncumul_vacc_doses, na.rm = FALSE)) %>%
  mutate(new_vacc_doses = ncumul_vacc_doses-lag(ncumul_vacc_doses, 1, default = 0)) %>%
  mutate(new_vacc_doses_7day = (ncumul_vacc_doses-lag(ncumul_vacc_doses,7, default = 0))/7)

#just 7-day-speed
ch_vacc_speed <- ch_vacc_proj %>%
  select(date, new_vacc_doses_7day) %>%
  mutate(new_vacc_doses_7day = round(new_vacc_doses_7day)) %>%
  filter(!is.na(new_vacc_doses_7day))

#write to Q-cli
update_chart(id = "b5f3df8202d94e6cba27c93a5230cd0e", 
             data = ch_vacc_speed)


dates_proj_ch <- seq(last(ch_vacc_proj$date)+1, as.Date("2099-12-31"), by="days")
ndays_proj_ch <- seq(1,length(dates_proj_ch), by = 1)

ch_vacc_esti <- ch_vacc_proj %>%
  filter(date >= last(date)-13) %>%
  summarise(  max_iqr = quantile(new_vacc_doses_7day, 0.75, na.rm = TRUE), 
              min_iqr = quantile(new_vacc_doses_7day, 0.25,na.rm = TRUE), 
              mean = mean(new_vacc_doses_7day, na.rm = TRUE))

vacc_proj_mean_ch <- ndays_proj_ch*ch_vacc_esti$mean + sum(ch_vacc_proj$new_vacc_doses, na.rm = T)
vacc_proj_max_iqr_ch <- ndays_proj_ch*ch_vacc_esti$max_iqr + sum(ch_vacc_proj$new_vacc_doses, na.rm = T)
vacc_proj_min_iqr_ch <- ndays_proj_ch*ch_vacc_esti$min_iqr + sum(ch_vacc_proj$new_vacc_doses, na.rm = T)

ch_vacc_proj_raw <- tibble(dates_proj_ch, vacc_proj_mean_ch, vacc_proj_max_iqr_ch, vacc_proj_min_iqr_ch)

herd_immunity_ch <-8644780*1.4
herd_immunity_date_ch <- first(ch_vacc_proj_raw$dates_proj_ch[vacc_proj_mean_ch > herd_immunity_ch])
herd_immunity_date_ch_max <- first(ch_vacc_proj_raw$dates_proj_ch[vacc_proj_min_iqr_ch > herd_immunity_ch])


#calculate goal
ch_vacc_goaldays <- length(ch_vacc_proj_raw$dates_proj_ch[ch_vacc_proj_raw$dates_proj_ch <= "2021-08-01"])
ch_vacc_goalspeed <- (herd_immunity_ch-last(ch_vacc_proj$ncumul_vacc_doses))/ch_vacc_goaldays
vacc_proj_goal_ch <- ndays_proj_ch*ch_vacc_goalspeed + sum(ch_vacc_proj$new_vacc_doses, na.rm = T)

ch_vacc_proj_raw_goal <- tibble(ch_vacc_proj_raw, vacc_proj_goal_ch)

ch_vacc_hi <- ch_vacc_proj_raw_goal %>% filter(dates_proj_ch <= herd_immunity_date_ch_max)

# clean off unneecessary data points
ch_vacc_hi$vacc_proj_mean_ch[ch_vacc_hi$vacc_proj_mean_ch >= herd_immunity_ch] <- NA
ch_vacc_hi$vacc_proj_max_iqr_ch[ch_vacc_hi$vacc_proj_max_iqr_ch >= herd_immunity_ch] <- NA
ch_vacc_hi$vacc_proj_min_iqr_ch[ch_vacc_hi$vacc_proj_min_iqr_ch >= herd_immunity_ch] <- NA
ch_vacc_hi$vacc_proj_goal_ch[ch_vacc_hi$vacc_proj_goal_ch >= herd_immunity_ch] <- NA

colnames(ch_vacc_hi) <- c("Datum",	"Momentante Geschwindigkeit", " ",	"Unsicherheitsbereich*", "Nötige Geschwindigkeit")

ch_past <- cbind(ch_vacc_proj[,1:2], NA, NA, NA)

colnames(ch_past) <- colnames(ch_vacc_hi)

ch_vacc_hi2 <- rbind(ch_past, ch_vacc_hi) %>%
  select(1,3,4,2,5)

# #which day?
# herd_immunity_date_ch
# 
# #which speed (now)?
# ch_vacc_esti$mean
# 
# #which speed (GOAL)?
# ch_vacc_goalspeed
# 
# #how many times faster need the vaccinations to happen?
# ch_vacc_goalspeed/ch_vacc_esti$mean

#write to Q-cli

update_chart(id = "37fc5e48506c4cd050bac04346238a2d", 
             data = ch_vacc_hi2,
             notes = paste0("* 25-Prozent- und 75-Prozent-Quantil des 7-Tage-Schnitts der letzten 14 Tage.<br>Stand: ",
                            ch_vacc_date))

#write to renv when adding new packages

# getwd()
# library(renv)
# init()
# snapshot()
# restore()

# fin
