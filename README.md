## Indexer

CLI daemon that schedules and invokes the indexer for configured apps.

### Database
- SQLite at `./data/indexer.db`
- Table `apps` columns:
  - `id TEXT PRIMARY KEY`
  - `yaml TEXT NOT NULL`
  - `last_run TEXT` (UTC ISO-8601, seconds = `00`)
  - `interval INTEGER` (nullable; > 0 when set)
  - `last_error TEXT`
  - `comments TEXT`
  

### Running
- Daemon (runs indefinitely):
  ```bash
  dart run bin/indexer_new.dart
  ```
  - Uses UTC minute precision. Every minute it finds due apps and invokes:
    ```bash
    echo $YAML | zapstore publish --indexer-mode
    ```

  

### Manage Apps
- Add/update an app from a YAML file (ID = filename):
  ```bash
  dart run bin/indexer_new.dart add path/to/app.yaml
  ```
  - Sets `id` to the basename of the file.
  - Sets `yaml` to file contents.
  - Defaults: `last_run` to today UTC midnight; `interval` to 360 minutes.

### Notes
 - All timestamps are UTC, truncated to minute.
 - Scheduling: run when `minutes_since_utc_midnight % interval == 0` (including minute 0 = midnight). After each run: update `last_run` and `last_error` only.

## Important

To find `signed.txt` contents: `select json_extract(value, '$[1]') as b_value from events, json_each(events.tags) where kind = 32267 and pubkey is not '78ce6faa72264387284e647ba6938995735ec8c7d5c5a65737e55130f026307d' and json_extract(value, '$[0]') = 'repository';`