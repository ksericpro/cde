# Subscriber (listen for alarms)
python3 /opt/cde/MQ/scripts/test_pubsub.py sub -u client_alarms -p alarmpass123 -t "cde/alarms/#"

# Publisher (send alarms)
python3 /opt/cde/MQ/scripts/test_pubsub.py pub -u cde-publisher -p cdepublisher123 -t "cde/alarms/critical" -m '{"severity":"CRITICAL","msg":"door forced open"}'