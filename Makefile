# 記事プレビュー用 Makefile
# sibling repo として hume-press (実装側) があることを前提に、その dev server を
# このリポジトリの articles/ を読み込ませて起動する。
#
# 使い方:
#   make preview          # localhost:4321 で dev server 起動 + ブラウザ自動オープン
#   make preview NO_OPEN=1 # ブラウザを開かない
#   HUME_PRESS=/path/to/hume-press make preview  # 実装側のパスを上書き

HUME_COM   := $(CURDIR)
HUME_PRESS ?= $(HUME_COM)/../hume-press
ASTRO_ARGS := $(if $(NO_OPEN),,--open)

.DEFAULT_GOAL := preview

.PHONY: preview deps

preview: deps
	cd $(HUME_PRESS) && ARTICLES_DIR=$(HUME_COM)/articles npm run dev -- $(ASTRO_ARGS)

deps:
	@if [ ! -d $(HUME_PRESS) ]; then \
		echo "hume-press not found at $(HUME_PRESS)"; \
		echo "ghq get github.com/shsw228/hume-press でクローンするか、HUME_PRESS=/path/to/hume-press で指定してください。"; \
		exit 1; \
	fi
	@if [ ! -d $(HUME_PRESS)/node_modules ]; then \
		echo "Installing hume-press dependencies..."; \
		cd $(HUME_PRESS) && npm install; \
	fi
