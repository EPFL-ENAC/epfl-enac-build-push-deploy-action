.PHONY: help install clean

VENV_DIR := .venv

help:
		@echo "Usage:"
		@echo "  make help       - Display this help message"
		@echo "  make install    - Install lefthook"
		@echo "  make clean      - Clean up the environment"

install: $(VENV_DIR)/bin/activate
		$(VENV_DIR)/bin/uv pip install lefthook
		npm install --global prettier

confirm-node:
		@read -p "Are you sure you want to uninstall prettier? [y/N] " ans; \
		if [ "$$ans" != "y" ]; then \
				echo "Uninstall cancelled."; \
				exit 1; \
		fi

uninstall-node-prettier: confirm-node
		npm uninstall --global prettier

confirm-python:
		@read -p "Are you sure you want to uninstall lefthook and remove .venv [y/N] " ans; \
		if [ "$$ans" != "y" ]; then \
				echo "Uninstall cancelled."; \
				exit 1; \
		fi


uninstall-python-deps: confirm-python
		$(VENV_DIR)/bin/uv pip uninstall lefthook
		rm -rf $(VENV_DIR)

clean: uninstall-python-deps  uninstall-node-prettier

run:
	act -W action.yml -s GITHUB_TOKEN=$(cat .secrets | grep GITHUB_TOKEN | cut -d '=' -f2) --env-file .env --eventpath event.json

$(VENV_DIR)/bin/activate: 
		python3 -m venv $(VENV_DIR)
		$(VENV_DIR)/bin/pip install uv
