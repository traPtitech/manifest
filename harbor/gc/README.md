# gc

Wasabiがなぜか `DeleteObject` は受け付けるが、`DeleteObjects` は受け付けないという謎仕様のため、registryのDELETE操作が上手くいかない

これに対するworkaroundとしての、手動GCスクリプトです
