# xml_tv
free_epg.pl

xmltv file from Freeview Australia

Usage:
        `free_epg.pl --region=<REGION-NAME> --file=<output xmltv filename>`

        REGION-NAME is one of the following:
                region_national
                region_nsw_sydney
                region_nsw_newcastle
                region_nsw_taree
                region_nsw_tamworth
                region_nsw_orange_dubbo_wagga
                region_nsw_northern_rivers
                region_nsw_wollongong
                region_nsw_canberra
                region_nt_regional
                region_vic_albury
                region_vic_shepparton
                region_vic_bendigo
                region_vic_melbourne
                region_vic_ballarat
                region_vic_gippsland
                region_qld_brisbane
                region_qld_goldcoast
                region_qld_toowoomba
                region_qld_maryborough
                region_qld_widebay
                region_qld_rockhampton
                region_qld_mackay
                region_qld_townsville
                region_qld_cairns
                region_sa_adelaide
                region_sa_regional
                region_wa_perth
                region_wa_regional_wa
                region_tas_hobart
                region_tas_launceston


hr_epg.pl

Simple script to create an xmltv file from the HDHomeRun internal epg.

Simply run `hr_epg.pl --help` to get a list of options.
Normal usage is: `./hr_epg.pl --output epg.xml`

Create a cron job to run the command every x hours/minutes to update the xml file.


yourtv.pl

yourtv.pl --region=94 --verbose --days=7 --output=out.xml
xmltv file from yourtv

Usage:
        `yourtv.pl --region=<REGION-NUMBER> --file=<output xmltv filename>`

        REGION-NUMBER is one of the following:
                101     =       Perth
                81      =       Adelaide
                88      =       Hobart
                94      =       Melbourne
                75      =       Brisbane
                73      =       Sydney
                126     =       Canberra
                74      =       Darwin
                83      =       Riverland
                342     =       Mandurah
                93      =       Geelong
                78      =       Gold Coast
                184     =       Newcastle
                293     =       Launceston
                255     =       Sunshine Coast
                86      =       Spencer Gulf
                343     =       Bunbury
                71      =       Wollongong
                90      =       Ballarat
                266     =       Bendigo
                82      =       Port Augusta
                256     =       Toowoomba
                344     =       Albany
                258     =       Wide Bay
                259     =       South Coast
                102     =       Regional WA
                98      =       Gippsland
                85      =       South East SA
                69      =       Tamworth
                66      =       Central Coast
                254     =       Rockhampton
                267     =       Shepparton
                253     =       Mackay
                268     =       Albury/Wodonga
                263     =       Taree/Port Macquarie
                261     =       Lismore
                95      =       Mildura/Sunraysia
                257     =       Townsville
                292     =       Coffs Harbour
                79      =       Cairns
                114     =       Remote and Central
                108     =       Regional NT
                262     =       Orange/Dubbo
                107     =       Remote and Central
                264     =       Wagga Wagga
                67      =       Griffith
                63      =       Broken Hill
                106     =       Remote and Central
                168     =       Foxtel
                371     =       Foxtel Now
                192     =       Optus TV feat. Foxtel
                284     =       Fetch


