# The made-up machines every screenshot launch seeds (`--ui-testing-seed-hosts`): name@address#collections:services.
# Enough of them, in collections, to fill the library as one in use does (the owner, 2026-10-30, of a library
# picture half empty: "There's a balance that needs to be had between showing the product and chaotic display").
# Sourced by shoot.sh, site_shots.sh and device_shots.sh.
HOSTS="alpha@192.0.2.10#Production:ssh+database|bravo@192.0.2.20#Office:ssh+rdp|nas@192.0.2.30#Home:ssh"
HOSTS+="|build@192.0.2.40#Production:ssh|win@192.0.2.50#Office:rdp|db@192.0.2.60#Production:ssh+database"
HOSTS+="|staging@192.0.2.70#Staging:ssh+database|pi@192.0.2.80#Home:ssh"
