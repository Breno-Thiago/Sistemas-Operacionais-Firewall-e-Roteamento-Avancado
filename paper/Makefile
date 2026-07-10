DOCUMENT=relatorio-academico
BUILD=build

.PHONY: pdf clean
pdf:
	mkdir -p $(BUILD)
	@if command -v latexmk >/dev/null 2>&1; then \
		latexmk -pdf -interaction=nonstopmode -halt-on-error -output-directory=$(BUILD) $(DOCUMENT).tex; \
	elif command -v docker >/dev/null 2>&1; then \
		docker run --rm --user "$$(id -u):$$(id -g)" -e HOME=/tmp \
			-v "$(abspath ..):/work" -w /work/paper texlive/texlive:latest-medium \
			latexmk -pdf -interaction=nonstopmode -halt-on-error \
			-output-directory=$(BUILD) $(DOCUMENT).tex; \
	else \
		echo "Instale latexmk/pdflatex ou Docker para gerar o PDF." >&2; exit 1; \
	fi

clean:
	rm -rf $(BUILD)
