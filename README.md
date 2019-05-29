# vscode-remote-forwarder

Visual Studio Code の Remote Development において、Remote - SSH から Docker コンテナへ接続するための補助的なシェルスクリプト.

    Visual Studio Code
       `- Remote SSH
             |
          SSH Host
             `- Docker
                  |-> Container1 (Go)
                  |-> Container2 (Python)
                  .
                  .

## Requirements

- SSH Host: `requester.sh` から `docker exec` を実行する権限. シェルクリプトを実行するためのコマンド(`socat` `sem`等).
- 各コンテナ: Visual Studio Code のリモートサーバーをインストールし実行ができる環境(Debian stretch slim ベースのイメージならば、wget と procps パッケージが必要).

## Installation

以下、SSH Host 上で実施.

- ディレクトリを作成し、`requester.sh` `forwarder.sh` を配置.
- `authorized_keys` へ鍵を登録するときに、以下のように `command` を指定(`/path/to` `USER` `CONTAINER` は環境に合わせて変更).

``` text
command="/path/to/requester.sh -u USER CONTAINER \"${SSH_ORIGINAL_COMMAND}\"" ssh-....
```

コンテナ内では、`-u` で指定したユーザーで Visual Studio Code のリモートサーバーが実行されます.

## Usage

- 接続先のコンテナを実行しておく.
- SSH Host 上で `forwarder.sh` を実行しておく.
- Visual Studio Code から、`authorized_keys` の設定を行った鍵で SSH Host へ接続.

## License

Copyright (c) 2019 hankei6km

Licensed under the MIT License. See LICENSE in the project root.
