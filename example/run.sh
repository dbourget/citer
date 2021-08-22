ruby ../citer.rb -i test.tex -o output.tex -b refs.bib && \
  pdflatex output && \
  bibtex output && \
  pdflatex output
