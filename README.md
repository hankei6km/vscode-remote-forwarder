# vscode-remote-forwarder

Visual Studio Code の Remote Development において、Remote - SSH から Docker コンテナへ接続するための補助的なシェルスクリプト.

    Visual Studio Code
       `- Remote SSH
             |
          SSH Host
             `- remote-forwarder
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
- `authorized_keys` へ鍵を登録するときに、以下のように `command` を指定(`'${HOME}/.bash_profile'` `/path/to` `USER` `CONTAINER` は環境に合わせて変更).

``` text
command="/path/to/requester.sh -s '${HOME}/.forwarder_env' -u USER CONTAINER \"${SSH_ORIGINAL_COMMAND}\"" ssh-....
```

コンテナ内では、`-u` で指定したユーザーで Visual Studio Code のリモートサーバーが実行されます.

`-s` で指定されたファイルは、コンテナ内で Visual Studio Code のリモートサーバーが実行されるときにインポート(`source`)されます. サーバーのインスタンスへ環境変数(例.`GOPATH`等)を与えることを想定しています
(インポートされるファイルはコンテナ内に配置します. またファイル名の展開もコンテナ内で実施されます).

## Usage

- 接続先のコンテナを実行しておく.
- SSH Host 上で `forwarder.sh` を実行しておく.
- Visual Studio Code から、`authorized_keys` の設定を行った鍵で SSH Host へ接続.

## Tips

### １つの鍵で複数のコンテナへ接続する

前提.

- SSH Host は Client からの `REMOTE_VSCODE_SEND*` 環境変数を受け付けるようにできる.
- 接続されるコンテナの名前を `vscode-remote-` で始まるようにできる.

SSH Host上での設定.

- SSH Host の設定で、クライアントからの環境変数 `REMOTE_VSCODE_SEND` を受け付けるようにする(`sshd_config` の`Match` ルールで `AcceptEnv REMOTE_VSCODE_SEND*` を指定する等).
- `authorized_keys` の記述を以下のように変更する.

``` text
command="CONTAINER=\"\"; for v in \"${!REMOTE_VSCODE_SEND@}\" ; do CONTAINER=\"${CONTAINER}${!v}\" ; done ; /path/to/requester.sh  -s '${HOME}/.forwarder_env' -u 1000 vscode-remote-\"${CONTAINER}\" \"${SSH_ORIGINAL_COMMAND}\"" ssh-...
```

クライアントPC上での設定.

- `REMOTE_VSCODE_SEND0=golang` `REMOTE_VSCODE_SEND1=extension` のようにコンテナ名の末尾を環境変数に設定(Visual Studio Code内でのみ利用なら`terminal.integrated.env.windows` 等で指定).
- `.ssh/config` へ以下のようにコンテナ毎の接続設定を作成.

      Host container-golang
          HostName foo
          User bar
          IdentityFile C:\Users\bar\.ssh\vscode-remote
          SendEnv REMOTE_VSCODE_SEND0
          .
          .
      Host container-extension
          HostName foo
          User bar
          IdentityFile C:\Users\bar\.ssh\vscode-remote
          SendEnv REMOTE_VSCODE_SEND1

以上の設定で、Visual Stuido Code の Host Explorer 等から `container-*` へ接続すると、`bar@foo` (`C:\Users\bar\.ssh\vscode-remote` 鍵を利用)への接続を経由し、それぞれのコンテナへ接続されるようになる.

## License

Copyright (c) 2019 hankei6km

Licensed under the MIT License. See LICENSE in the project root.
