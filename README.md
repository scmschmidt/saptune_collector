# saptune_collector

Retrieve saptune data and present them as metrics for prometheus node_exporter's textfile collector.

:exclamation: **This repo is to present code snippets for ((BLOG LINK)) only. It is not meant as a growing maintained project. Use the code as it is and adapt it to your needs. **


## The collector script: `saptune_collector.sh`

The script executes various saptune checks and writes a prometheus metric description to stdout.

Contrary to the saptune-exporter (https://github.com/SUSE/saptune_exporter), the script collects
different information and uses different metric names:

| Name                            | Type  | Description | Example | 
| ---                             | ---   | --- | --- | 
| `sc_timestamp`                  | gauge | Timestamp (epoch) when metrics were generated. | `sc_timestamp 1646841231` |
| `sc_saptune`                    | gauge | Contains saptune version information (configured and package). | `sc_saptune{version="3",package="saptune-3.0.2-8.22.2.x86_64"} 1` |
| `sc_saptune_service_active`     | gauge | Tells if `saptune.service` is active (1) or not (0).  | `sc_saptune_service_active 1` | 
| `sc_saptune_service_enabled`    | gauge | Tells if `saptune.service` is enabled (1) or not (0). | `sc_saptune_service_enabled 1` | 
| `sc_saptune_note_enabled`       | gauge | Lists all available Notes and if they're enabled by a solution (1), enabled manually (2), reverted (3) or not enabled at all (0). " | `saptune_note_enabled{note_desc="Linux: User and system resource limits",note_id="1771258"} 1` |
| `sc_saptune_note_applied`       | gauge | Lists all available Notes and if they're applied  (1) or not (0). | `saptune_note_applied{note_desc="Linux: User and system resource limits",note_id="1771258"} 1` |
| `sc_saptune_solution_enabled`   | gauge | Lists all available Solutions and if it is enabled (1) or not (0). | `sc_saptune_solution_enabled{solution_name="HANA"} 1` |
| `sc_saptune_solution_applied`   | gauge | Lists all available Solutions and if it is applied (1) or not (0).  | `sc_saptune_solution_applied{solution_name="HANA"} 1` |
| `sc_saptune_note_verify`        | gauge | Shows for each applied Notes if it is compliant (1) or not (0) and why (base64)." | `sc_saptune_note_verify{note_id="941735", output="..." 1` | 
| `sc_saptune_compliance`         | gauge | Shows overall compliance of all applied Notes: yes (1) or no (0). | `sc_saptune_compliance 1` | 

 
### Usage with the prometheus textfile collector

To be used by the textfile collector of the prometheus node exporter, the output needs to put into a file which should be updated regularly.
This can be achieved by a systemd timer. 

### `saptune_collector.service`

```
[Unit]
Description=Collects saptune metrics for prometheus textfile collector.
 
[Service]
Type=oneshot
ExecStartPre=/usr/bin/rm -f <path_to_data_file>  
ExecStart=/bin/sh -c 'exec <path_to_saptune_collector.sh > <path_to_data_file>.tmp'
ExecStartPost=/usr/bin/mv <path_to_data_file>.tmp <path_to_data_file>
```

### `saptune_collector_timer`

```
[Unit]
Description=Periodic collection of saptune metrics for prometheus textfile collector.

[Timer]
Unit=saptune_collector.service
OnCalendar=*:0/15
RandomizedDelaySec=10

[Install]
WantedBy=timers.target
```

## Installing
                                                              
1. Put `saptune_collector.sh` to `/usr/local/sbin/`.
                                                              
2. Create `saptune_collector.service` and `saptune_collector_timer` in `/etc/systemd/system/`.

3. Add the following argument to the line `ARGS=` in `/etc/sysconfig/prometheus-node_exporter`: `--collector.textfile.directory=<directory_with_data_file>`

4. Execute: 
 
   ``` 
   ~ # systemctl daemon-reload 
   ~ # systemctl restart prometheus-node_exporter 
   ~ # systemctl enable --now saptune_collector.timer 
   ``` 
