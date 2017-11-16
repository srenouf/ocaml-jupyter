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

open Format
open OUnit2
open Jupyter.Iopub
open Jupyter.Shell
open Jupyter_repl.Evaluation

let pp_status ppf status =
  [%to_yojson: Jupyter.Shell.status] status
  |> Yojson.Safe.to_string
  |> pp_print_string ppf

let pp_reply ppf reply =
  [%to_yojson: Jupyter.Iopub.reply] reply
  |> Yojson.Safe.to_string
  |> pp_print_string ppf

let eval ?(count = 0) code =
  let replies = ref [] in
  let send r = replies := r :: !replies in
  let status = eval ~send ~count code in
  (status, List.rev !replies)

let test__simple_phrase ctxt =
  let status, actual = eval "let x = (4 + 1) * 3" in
  let expected = [iopub_success ~count:0 "val x : int = 15\n"] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_OK status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__multiple_phrases ctxt =
  let status, actual = eval
      "let x = (4 + 1) * 3\n\
       let y = \"Hello \" ^ \"World\"\n\
       let z = List.map (fun x -> x * 2) [1; 2; 3]\n" in
  let expected = [
    iopub_success ~count:0 "val x : int = 15\n";
    iopub_success ~count:0 "val y : string = \"Hello World\"\n";
    iopub_success ~count:0 "val z : int list = [2; 4; 6]\n";
  ] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_OK status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__directive ctxt =
  let status, actual = eval "#load \"str.cma\" ;; Str.regexp \".*\"" in
  let expected = [iopub_success ~count:0 "- : Str.regexp = <abstr>\n"] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_OK status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__external_command ctxt =
  let status, actual = eval "Sys.command \"ls -l >/dev/null 2>/dev/null\"" in
  let expected = [iopub_success ~count:0 "- : int = 0\n"] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_OK status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__syntax_error ctxt =
  let status, actual = eval ~count:123 "let let let\nlet" in
  let expected =
    [error ~value:"compile_error"
       ["\x1b[31mFile \"[123]\", line 1, characters 4-7:\
         \nError: Syntax error\n\x1b[0m"]] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_ERROR status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__unbound_value ctxt =
  let status, actual = eval ~count:123 "foo 42" in
  let expected =
    [error ~value:"compile_error"
       ["\x1b[31mFile \"[123]\", line 1, characters 0-3:\
         \nError: Unbound value foo\n\x1b[0m"]] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_ERROR status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__type_error ctxt =
  let status, actual = eval ~count:123 "42 = true" in
  let expected =
    [error ~value:"compile_error"
       ["\x1b[31mFile \"[123]\", line 1, characters 5-9:\
         \nError: This expression has type bool but an expression was expected of type\
         \n         int\n\x1b[0m"]] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_ERROR status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__long_error_message ctxt =
  let status, actual = eval ~count:123
      "let a = 42 in\n\
       let b = 43 in\n\
       let c = foo in\n\
       let d = 44 in\n\
       ()"
  in
  let expected =
    [error ~value:"compile_error"
       ["\x1b[31mFile \"[123]\", line 3, characters 8-11:\
         \nError: Unbound value foo\n\x1b[0m"]] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_ERROR status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__exception ctxt =
  let status, actual = eval "failwith \"FAIL\"" in
  let msg =
    if Sys.ocaml_version <= "4.02.3"
    then "\x1b[31mException: Failure \"FAIL\".\n\x1b[0m"
    else "\x1b[31mException: Failure \"FAIL\".\n\
          Raised at file \"pervasives.ml\", line 32, characters 22-33\n\
          Called from file \"toplevel/toploop.ml\", line 180, characters 17-56\n\x1b[0m"
  in
  let expected = [error ~value:"runtime_error" [msg]] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_ERROR status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__unknown_directive ctxt =
  let status, actual = eval "#foo" in
  let expected = [error ~value:"runtime_error"
                    ["\x1b[31mUnknown directive `foo'.\n\x1b[0m"]] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_ERROR status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__ppx ctxt =
  let status, actual = eval "#require \"ppx_deriving.show\" ;; \
                             type t = { x : int } [@@deriving show]" in
  let expected =
    [iopub_success ~count:0
       "type t = { x : int; }\n\
        val pp : Format.formatter -> t -> Ppx_deriving_runtime.unit = <fun>\n\
        val show : t -> Ppx_deriving_runtime.string = <fun>\n"] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_OK status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let test__camlp4 ctxt =
  let _ = eval "#camlp4o ;;" in
  let status, actual = eval "[< '1 ; '2 >]" in
  let expected = [iopub_success ~count:0 "- : int Stream.t = <abstr>\n"] in
  assert_equal ~ctxt ~printer:[%show: status] SHELL_OK status ;
  assert_equal ~ctxt ~printer:[%show: reply list] expected actual

let suite =
  "Evaluation" >::: [
    "eval" >::: [
      "simple_phrase" >:: test__simple_phrase;
      "multiple_phrases" >:: test__multiple_phrases;
      "directive" >:: test__directive;
      "external_command" >:: test__external_command;
      "syntax_error" >:: test__syntax_error;
      "unbound_value" >:: test__unbound_value;
      "type_error" >:: test__type_error;
      "long_error_message" >:: test__long_error_message;
      "exception" >:: test__exception;
      "unknown_directive" >:: test__unknown_directive;
      "ppx" >:: test__ppx;
      "camlp4" >:: test__camlp4;
    ]
  ]

let () =
  init ~init_file:"fixtures/ocamlinit.ml" () ;
  run_test_tt_main suite
