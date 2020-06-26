Changelog
=========

0.4 (2020-06-26)
----------------

- Add option to select inputs to check for CMCIII-IO3 devices
  - **Breaking**: All inputs have been checked before
- Add support to check multiple devices with one check
- Add flag to use device alias as status label (CMCIII-LEAK)
- Change scan output to be more verbose
- Add additional checks for CMCIII-PU
  - Check state of input sensors
  - Check temperature sensor
  - Check access sensor
- Add support for CMCIII-ACC sensor
- Add flag to use sensor name as status label for access sensors(CMCIII-ACC, CMCIII-PU)
- Fix compilation error with newer Perl versions

0.3 (2017-05-22)
----------------

- Add support for CMCIII-LEAK sensor
- Add support for CMCIII-IO3 sensor

0.2 (2015-10-30)
----------------

- Add scan option to show all 
- Add support for CMCIII-HUM sensor
- Add support for CMCIII-PU temperature sensor
- Add option to filter sensors to read
- Add support to read current, voltage and power from PSM-M16 sensor

0.1 (2015-10-28)
----------------

- Add support for Nagios and Monitoring plugin
- Add support for CMCIII-TMP sensor
