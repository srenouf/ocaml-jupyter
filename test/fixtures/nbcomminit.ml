#use "topfind" ;;
#thread ;;
#require "yojson,base64,uuidm,ppx_deriving.runtime,ppx_deriving_yojson.runtime" ;;
#directory "../jupyter/src/core" ;;
#directory "../jupyter/src/notebook" ;;
#directory "../jupyter/src/comm" ;;
#load "../jupyter/src/core/jupyter.cma" ;;
#load "../jupyter/src/notebook/jupyter_notebook.cma" ;;
#load "../jupyter/src/comm/jupyter_comm.cma" ;;
