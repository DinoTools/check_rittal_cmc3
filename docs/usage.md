Usage
=====

Scan for devices
----------------

Scan for devices connected to the CMC3 unit.

```shell
./check_rittal_cmc3.pl --hostname=1.2.3.4 --community=your-community-string --scan
 ID | Name               | Description
----|--------------------|---------------------------------
  1 | CMCIII-PU          | CMCIII-PU
  2 | PSM-M16            | My Power System Modul
  3 | CMCIII-TMP         | Example Room
  4 | CMCIII-HUM         | Example Rack
```

Run Check
---------

In the examples below we use the ```CMCIII-HUM``` device with the ID 4.

### Check all sensors

First we check all sensors.

```shell
./check_rittal_cmc3.pl --hostname=1.2.3.4 --community=your-community-string --device 4
check_rittal_cmc3 OK - Humidity: 21% Temperature: 20.1°C | humidity=21%;10:60;5:70 temperature=20.1;10:25;5:30
```

### Check temperature sensors

Let's check only the temperature

```shell
./check_rittal_cmc3.pl --hostname=1.2.3.4 --community=your-community-string --device 4 --sensor temperature
check_rittal_cmc3 OK - Temperature: 20.1°C | temperature=20.1;10:25;5:30
```

### Check humidity sensors

Let's check only the humidity

```shell
./check_rittal_cmc3.pl --hostname=1.2.3.4 --community=your-community-string --device 4 --sensor humidity
check_rittal_cmc3 OK - Humidity: 21% | humidity=21%;10:60;5:70
```

Thresholds
----------

All thresholds are fetched from CMC3 unit. If you want to change them login to the admin interface of the CMC3 unit and modify them as you like.
