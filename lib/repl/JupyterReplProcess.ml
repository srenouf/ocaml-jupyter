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

(** OCaml REPL process *)

open Format
open Lwt.Infix
open JupyterReplMessage

type t =
  {
    pid : int;
    stream : JupyterReplMessage.output Lwt_stream.t;
    push : JupyterReplMessage.output option -> unit;
    ctrlout : Lwt_io.input Lwt_io.channel;
    ctrlin : Lwt_io.output Lwt_io.channel;
    stdout : Lwt_io.input Lwt_io.channel;
    stderr : Lwt_io.input Lwt_io.channel;
    recv_stdout : unit Lwt.t;
    recv_stderr : unit Lwt.t;
  }

type input = JupyterReplMessage.reply
type output = JupyterReplMessage.request

let flags = [] (** marshal flags *)

let create_child_process ?preload ?init_file ctrlin ctrlout =
  JupyterReplToploop.init ?preload ?init_file () ;
  let rec aux () =
    match Marshal.from_channel ctrlin with
    | exception End_of_file -> exit 0
    | Quit -> exit 0 (* Shutdown request *)
    | Exec (filename, code) ->
      JupyterReplToploop.run ~filename code
        ~f:(fun () resp -> Marshal.to_channel ctrlout resp flags)
        ~init:() ;
      Marshal.to_channel ctrlout Prompt flags ;
      flush ctrlout ;
      aux ()
  in
  aux ()

let recv_output_thread ~push ~f ic =
  let rec loop () =
    Lwt_io.read_line ic >>= fun line ->
    push (Some (f (line ^ "\n"))) ;
    loop ()
  in
  loop ()

let create ?preload ?init_file () =
  let c_ctrlin, p_ctrlin = Unix.pipe () in
  let p_ctrlout, c_ctrlout = Unix.pipe () in
  let p_stdout, c_stdout = Unix.pipe () in
  let p_stderr, c_stderr = Unix.pipe () in
  match Unix.fork () with
  | 0 ->
    Unix.close p_ctrlin ;
    Unix.close p_ctrlout ;
    Unix.close p_stdout ;
    Unix.close p_stderr ;
    Unix.dup2 c_stdout Unix.stdout ;
    Unix.dup2 c_stderr Unix.stderr ;
    Unix.close c_stdout ;
    Unix.close c_stderr ;
    create_child_process ?preload ?init_file
      (Unix.in_channel_of_descr c_ctrlin)
      (Unix.out_channel_of_descr c_ctrlout)
  | pid ->
    Unix.close c_ctrlin ;
    Unix.close c_ctrlout ;
    Unix.close c_stdout ;
    Unix.close c_stderr ;
    let (stream, push) = Lwt_stream.create () in
    let ctrlout = Lwt_io.(of_unix_fd ~mode:input p_ctrlout) in
    let stdout = Lwt_io.(of_unix_fd ~mode:input p_stdout) in
    let stderr = Lwt_io.(of_unix_fd ~mode:input p_stderr) in
    {
      pid; stream; push; ctrlout; stdout; stderr;
      ctrlin = Lwt_io.(of_unix_fd ~mode:output p_ctrlin);
      recv_stdout = recv_output_thread ~push ~f:(fun s -> Stdout s) stdout;
      recv_stderr = recv_output_thread ~push ~f:(fun s -> Stderr s) stderr;
    }

let stream repl = repl.stream

let send repl (req : output) =
  Lwt_io.write_value repl.ctrlin req ~flags >>= fun () ->
  Lwt_io.flush repl.ctrlin

let recv repl : JupyterReplMessage.reply Lwt.t = Lwt_io.read_value repl.ctrlout

let close repl =
  let%lwt () = send repl Quit in (* Send shutdown request *)
  let%lwt (_, proc_status) = Lwt_unix.(waitpid [WUNTRACED] repl.pid) in
  Lwt.cancel repl.recv_stdout ;
  Lwt.cancel repl.recv_stderr ;
  let%lwt () = Lwt.join [
      Lwt_io.close repl.ctrlin;
      Lwt_io.close repl.ctrlout;
      Lwt_io.close repl.stdout;
      Lwt_io.close repl.stderr;
    ] in
  repl.push None ; (* close a stream *)
  match proc_status with
  | Unix.WEXITED 0 -> Lwt.return_unit (* success *)
  | Unix.WEXITED i -> failwith (sprintf "REPL process exited status %d" i)
  | Unix.WSIGNALED i -> failwith (sprintf "REPL process killed by signal %d" i)
  | Unix.WSTOPPED i -> failwith (sprintf "REPL process stopped by signal %d" i)

let interrupt repl =
  Unix.kill repl.pid Sys.sigint
