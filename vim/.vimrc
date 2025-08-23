" ===== Minimal Vim Config =====

Enable line numbers
set number
set relativenumber

" Highlight matching brackets
set showmatch

" Enable basic syntax highlighting (not fancy themes)
syntax on

" Indentation settings
set tabstop=4       " Number of spaces a <Tab> counts for
set shiftwidth=4    " Number of spaces used for auto-indent
set expandtab       " Use spaces instead of tabs

" Searching
set ignorecase      " Case-insensitive search
set smartcase       " Case-sensitive if uppercase is used
set hlsearch        " Highlight search results
set incsearch       " Show matches as you type

" File handling
set autoindent      " Auto-indent new lines
set backspace=indent,eol,start " Make backspace behave normally

" Keep a bit of context when scrolling
set scrolloff=3

" Disable swap files (optional, if you don’t like them)
set noswapfile

