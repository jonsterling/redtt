{
open Grammar
open Lexing

module type SOURCE = sig
  val on_refill : lexbuf -> unit Lwt.t
end

module type LEXER = sig
  val token : lexbuf -> Grammar.token Lwt.t
end
type lexer = (module LEXER)

module Make (R : SOURCE) : LEXER = struct
  open Lwt.Infix

  let refill_handler k lexbuf =
    R.on_refill lexbuf >>= fun _ -> k lexbuf

  let make_table num elems =
    let table = Hashtbl.create num in
    List.iter (fun (k, v) -> Hashtbl.add table k v) elems;
    table


  module BlockComment =
  struct
    let depth = ref 0

    let push () =
      depth := !depth + 1

    let pop () =
      depth := !depth - 1;
      if !depth = 0 then `Token else `Comment
  end

  let keywords =
    make_table 0 [
      ("V", V);
      ("opaque", OPAQUE);
      ("print", PRINT);
      ("meta", META);
      ("quit", QUIT);
      ("in", IN);
      ("with", WITH);
      ("where", WHERE);
      ("data", DATA);
      ("end", END);
      ("tick", TICK);
      ("✓", TICK);
      ("dim", DIM);
      ("𝕀", DIM);
      ("elim", ELIM);
      ("fst", FST);
      ("snd", SND);
      ("coe", COE);
      ("com", COM);
      ("pair", PAIR);
      ("hcom", HCOM);
      ("comp", COMP);
      ("vproj", VPROJ);
      ("vin", VIN);
      ("let", LET);
      ("do", DO);
      ("fun", FUN);
      ("def", DEF);
      ("lam", LAM);
      ("next", NEXT);
      ("prev", PREV);
      ("dfix", DFIX);
      ("fix", FIX);
      ("call", CALL);
      ("refl", REFL);
      ("pre", PRE);
      ("kan", KAN);
      ("U", UNIV);
      ("debug", DEBUG);
      ("normalize", NORMALIZE);
      ("type", TYPE);
      ("import", IMPORT);
    ]
}

let line_ending
  = '\r'
  | '\n'
  | "\r\n"
let number =
  ['0'-'9']+
let whitespace =
  [' ' '\t']+
let atom_initial =
  [^ '0'-'9' '-' '?' '!' '(' ')' '[' ']' '{' '}' '<' '>' '.' '#' '\\' '@' '*' '^' ':' ',' ';' '|' '=' '"' '`' ' ' '\t' '\n' '\r']
let atom_subsequent =
  [^                     '(' ')' '[' ']' '{' '}' '<' '>' '.' '#' '\\' '@' '*' '^' ':' ',' ';' '|' '=' '"' ' ' '\t' '\n' '\r']

refill {refill_handler}

rule token = parse
  | number
    { Lwt.return (NUMERAL (int_of_string (Lexing.lexeme lexbuf))) }
  | "--"
    { line_comment lexbuf }
  | "/-"
    { BlockComment.push (); block_comment lexbuf }
  | '('
    { Lwt.return LPR }
  | ')'
    { Lwt.return RPR }
  | '['
    { Lwt.return LSQ }
  | ']'
    { Lwt.return RSQ }
  | '{'
    { Lwt.return LBR }
  | '}'
    { Lwt.return RBR }
  | '#'
    { Lwt.return HASH }
  | '!'
    { Lwt.return BANG }
  | '@'
    { Lwt.return AT }
  | '`'
    { Lwt.return BACKTICK }
  | '|'
    { Lwt.return PIPE }
  | '^'
    { Lwt.return CARET }
  | '*'
    { Lwt.return AST }
  | "×"
    { Lwt.return TIMES }
  | ':'
    { Lwt.return COLON }
  | ';'
    { Lwt.return SEMI }
  | ','
    { Lwt.return COMMA }
  | '.'
    { Lwt.return DOT }
  | "∂"
    { Lwt.return BOUNDARY }
  | ":>"
    { Lwt.return TRIANGLE_RIGHT }
  | "▷"
    { Lwt.return TRIANGLE_RIGHT }
  | '='
    { Lwt.return EQUALS }
  | "->"
    { Lwt.return RIGHT_ARROW }
  | "→"
    { Lwt.return RIGHT_ARROW }
  | "<"
    { Lwt.return LGL }
  | ">"
    { Lwt.return RGL }
  | "λ"
    { Lwt.return LAM }
  | "\\"
    { Lwt.return LAM }
  | line_ending
    { new_line lexbuf; token lexbuf }
  | whitespace
    { token lexbuf }
  | eof
    { Lwt.return EOF }
  | "?" atom_initial atom_subsequent*
    {
      match String.split_on_char '?' @@ lexeme lexbuf with
      | [] ->
        Lwt.return @@ Grammar.HOLE_NAME None
      | _ :: input ->
        let name = String.concat "" input in
        Lwt.return (Grammar.HOLE_NAME (Some name))
    }
  | "?"
    { Lwt.return (Grammar.HOLE_NAME None) }
  | atom_initial atom_subsequent*
    {
      let input = lexeme lexbuf in
      begin try
        let kwd = Hashtbl.find keywords input in
        Lwt.return kwd
      with Not_found ->
        Lwt.return (Grammar.ATOM input)
      end
    }
  | _
    { Lwt_io.printlf "Unexpected char: %s" (lexeme lexbuf) >>= fun _ -> failwith "Lexing error" }

and line_comment = parse
  | line_ending
    { new_line lexbuf; token lexbuf }
  | _
    { line_comment lexbuf }

and block_comment = parse
  | "/-"
    { BlockComment.push ();
      block_comment lexbuf
    }
  | "-/"
    { match BlockComment.pop () with
      | `Token -> token lexbuf
      | `Comment -> block_comment lexbuf }
  | _
    { block_comment lexbuf }

{
end (* LEXER *)

module type STATE = sig
  val chan : Lwt_io.input_channel
  val size : int
end

module LwtSource (S : STATE) : SOURCE = struct
  open Lwt.Infix

  let resize b n =
    if (b.lex_buffer_len + n) > (Bytes.length b.lex_buffer) then begin
      let tmp_buf = ref b.lex_buffer in
      if (b.lex_buffer_len - b.lex_start_pos + n) > Bytes.length b.lex_buffer then begin
        let new_len = min (2 * Bytes.length b.lex_buffer) Sys.max_string_length in
        if b.lex_buffer_len - b.lex_start_pos + n > new_len then
          failwith "cannot resize buffer"
        else
          tmp_buf := Bytes.create new_len
      end;
      Bytes.blit b.lex_buffer b.lex_start_pos !tmp_buf 0 (b.lex_buffer_len - b.lex_start_pos);
      b.lex_buffer <- !tmp_buf;
      for i = 0 to Array.length b.lex_mem - 1 do
        if b.lex_mem.(i) >= 0 then
          b.lex_mem.(i) <- b.lex_mem.(i) - b.lex_start_pos
      done;
      b.lex_abs_pos    <- b.lex_abs_pos    + b.lex_start_pos;
      b.lex_curr_pos   <- b.lex_curr_pos   - b.lex_start_pos;
      b.lex_last_pos   <- b.lex_last_pos   - b.lex_start_pos;
      b.lex_buffer_len <- b.lex_buffer_len - b.lex_start_pos;
      b.lex_start_pos  <- 0;
    end

  let on_refill b =
    let aux_buffer = Bytes.create S.size in
    Lwt_io.read_into S.chan aux_buffer 0 S.size >>= fun n ->
    if n = 0 then
      Lwt.return (b.lex_eof_reached <- true)
    else begin
      resize b n;
      Bytes.blit aux_buffer 0 b.lex_buffer b.lex_buffer_len n;
      Lwt.return (b.lex_buffer_len <- b.lex_buffer_len + n)
    end
end

let create ?(file_name = "") chan size =
  let pkg : lexer = (module Make(LwtSource(struct
    let chan = chan
    let size = size
  end))) in
  let zero_pos = {
    pos_fname = file_name;
    pos_lnum  = 1;
    pos_bol   = 0;
    pos_cnum  = 0;
  } in
  let buf = {
    refill_buff     = begin fun _ -> () end;
    lex_buffer      = Bytes.create size;
    lex_buffer_len  = 0;
    lex_abs_pos     = 0;
    lex_start_pos   = 0;
    lex_curr_pos    = 0;
    lex_last_pos    = 0;
    lex_last_action = 0;
    lex_mem         = [| |];
    lex_eof_reached = false;
    lex_start_p     = zero_pos;
    lex_curr_p      = zero_pos;
  } in (pkg, buf)

let tokens ?(file_name = "") chan =
  let open Lwt.Infix in
  let len = 1024 in
  let (pkg, buf) = create ~file_name chan len in
  let module Lwt_lex = (val pkg : LEXER) in
  let go () =
    Lwt_lex.token buf >>= fun tok ->
    Lwt.return (Some tok)
  in (buf, Lwt_stream.from go)
}
