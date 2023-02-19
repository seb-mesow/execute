TEX_ARGS=-interaction batchmode -synctex=4
LUATEX_ARGS=--interaction=batchmode --synctex=4

PDFTEX=pdftex -8bit $(TEX_ARGS)
PDFLATEX=pdflatex $(TEX_ARGS)
LUATEX=luatex $(LUATEX_ARGS)
LUALATEX=lualatex $(LUATEX_ARGS)

TEX=$(LUATEX)
LATEX=$(LUALATEX)

MAKEINDEX_INDEX=makeindex -s gind.ist
MAKEINDEX_GLOSSARY=makeindex -s gglo.ist


REMOVE_HELP_FILES_EXT=\
	akc,aks,aux,bbl,bcf,bit,blg,ps,dvi,ent,fac,fdb_latexmk,fls,glo,idx,ilg,ind,lof,log,lot,nav,out,snm,tac,tdo,toc,upa,vrb,xwm,synctex\(busy\),synctex\(busy\).gz,recover.bak~,dtxe,hd
REMOVE_DIST_FILES_EXT=\
	synctex,synctex.gz,pdf

execute.lua: latex-env.tex

execute.tex: execute.lua

execute-test.pdf: execute-test.tex execute.tex
	$(LUATEX) $<

execute-test-short.pdf: execute-test-short.tex execute.tex
	$(LUATEX) $<

clean:
	rm -f *.{$(REMOVE_HELP_FILES_EXT)}

distclean: clean
	rm -f *.{$(REMOVE_DIST_FILES_EXT)}
	rm -f $(MAIN).cls
