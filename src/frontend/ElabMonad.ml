open RedBasis open Bwd open BwdNotation
open RedTT_Core

module C = Contextual
module U = Unify

type location = (Lexing.position * Lexing.position) option

type diagnostic =
  | UserHole of
      {name : string option;
       tele : U.telescope;
       ty : Tm.tm;
       tm : Tm.tm}

type 'a m = ('a * (location * diagnostic) bwd) C.m

let optional (m : 'a m) : 'a option m =
  C.bind (C.optional m) @@ function
  | None -> C.ret (None, Emp)
  | Some (a, ds) -> C.ret (Some a, ds)

let ret a =
  C.ret (a, Emp)

let bind m k =
  C.bind m @@ fun (a, w) ->
  C.bind (k a) @@ fun (b, w') ->
  C.ret (b, w <.> w')

let lift m =
  C.bind m ret

let emit l d =
  C.ret ((), Emp #< (l, d))

let normalize_param p =
  let module Notation = Monad.Notation (C) in
  let open Notation in

  C.base_cx >>= fun cx ->
  let normalize_ty ty =
    let vty = Cx.eval cx ty in
    Cx.quote_ty cx vty
  in
  match p with
  | `P ty ->
    C.ret @@ `P (normalize_ty ty)
  | `Tw (ty0, ty1) ->
    C.ret @@ `Tw (normalize_ty ty0, normalize_ty ty1)
  | (`I | `Tick | `Lock | `ClearLocks | `KillFromTick _ | `SelfArg Desc.Self) as p ->
    C.ret p
  | `R (r0, r1) ->
    C.ret @@ `R (r0, r1)

let rec normalize_tele =
  let module Notation = Monad.Notation (C) in
  let open Notation in
  function
  | [] -> C.ret []
  | (x, p) :: tele ->
    normalize_param p >>= fun p ->
    C.in_scope x p (normalize_tele tele) >>= fun psi ->
    C.ret @@ (x,p) :: psi

let pp_message ~loc ~tag pp fmt data =
  match loc with
  | None ->
    pp fmt data
  | Some (start_pos, end_pos) ->
    let open Lexing in
    Format.fprintf fmt "@[%a:%i.%i-%i.%i [%a]:@,  @[%a@]@]"
      Uuseg_string.pp_utf_8 start_pos.pos_fname
      start_pos.pos_lnum
      (start_pos.pos_cnum - end_pos.pos_bol)
      end_pos.pos_lnum
      (end_pos.pos_cnum - end_pos.pos_bol)
      Uuseg_string.pp_utf_8 tag
      pp data

let print_diagnostic =
  function
  | (loc, UserHole {name; tele; ty; _}) ->
    C.local (fun _ -> tele) @@
    begin
      C.bind C.base_cx @@ fun cx ->
      C.bind (normalize_tele @@ Bwd.to_list tele) @@ fun tele ->
      let vty = Cx.eval cx ty in
      let ty = Cx.quote_ty cx vty in
      let pp fmt () =
        Format.fprintf fmt "?%s:@,  @[<v>@[<v>%a@]@,%a %a@]@.@."
          (match name with Some name -> name | None -> "Hole")
          Dev.pp_params (Bwd.from_list tele)
          Uuseg_string.pp_utf_8 "⊢"
          Tm.pp0 ty
      in
      pp_message ~loc ~tag:"Info" pp Format.std_formatter ();
      C.ret ()
    end

let rec print_diagnostics =
  function
  | Emp ->
    C.ret ()
  | Snoc (w, d) ->
    C.bind (print_diagnostics w) @@ fun _ ->
    print_diagnostic d

let report (m : 'a m) : 'a m =
  C.bind m @@ fun (a, w) ->
  C.bind (C.dump_state Format.err_formatter "Unsolved:" `Unsolved) @@ fun _ ->
  C.bind (print_diagnostics w) @@ fun _ ->
  ret a


let under_restriction r r' (m : 'a m) : 'a option m =
  C.bind (C.under_restriction r r' m) @@ function
  | None ->
    ret None
  | Some (x, ds) ->
    C.ret (Some x, ds)

let in_scopes = C.in_scopes
let in_scope = C.in_scope
let isolate = C.isolate
let unify = lift @@ C.bind C.go_to_top @@ fun _ -> C.local (fun _ -> Emp) U.ambulando
let local = C.local


let run m =
  fst @@ C.run m
