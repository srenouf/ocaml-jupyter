(* ocaml-jupyter --- An OCaml kernel for Jupyter

   Copyright (c) 2017 Akinori ABE

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE. *)

(** Kernel server *)

module Make
    (ShellChannel : JupyterChannelIntf.Shell)
    (IopubChannel : JupyterChannelIntf.Iopub)
    (StdinChannel : JupyterChannelIntf.Stdin)
    (Repl : JupyterChannelIntf.Repl) :
sig
  (** The type of servers. *)
  type t =
    {
      repl : Repl.t;
      shell : ShellChannel.t;
      control : ShellChannel.t;
      iopub : IopubChannel.t;
      stdin : StdinChannel.t;

      mutable execution_count : int;
      mutable current_parent : ShellChannel.input option;
    }

  (** Connect to Jupyter. *)
  val create : repl:Repl.t -> ctx:ZMQ.Context.t -> JupyterConnectionInfo.t -> t

  (** Close connection to Jupyter. *)
  val close : t -> unit Lwt.t

  (** Start a server thread accepting requests from Jupyter. *)
  val start : t -> unit Lwt.t
end
