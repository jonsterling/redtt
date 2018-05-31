(* Experimental code *)

open Unify open Dev open Contextual open RedBasis open Bwd open BwdNotation
module Notation = Monad.Notation (Contextual)
open Notation

module T = PersistentTable.M

type edecl =
  | Make of string * escheme
  | Refine of string * eterm
  | Debug

and escheme = eterm

and eterm =
  | Hole
  | Var of string
  | Lam of string * eterm
  | Pair of eterm * eterm
  | Type
  | Quo of (ResEnv.t -> tm)

(* e-sigarette ;-) *)
type esig =
  edecl list

let univ = Tm.univ ~lvl:Lvl.Omega ~kind:Kind.Pre

let get_tele =
  ask >>= fun psi ->
  let go (x, p) =
    match p with
    | P ty -> x, ty
    | _ -> failwith "get_tele"
  in
  ret @@ Bwd.map go psi

let get_resolver =
  let rec go renv =
    function
    | Emp -> renv
    | Snoc (psi, (x, _)) ->
      let renvx = ResEnv.global (Name.to_string x) x renv in
      go renvx psi
  in
  ask >>= fun psi ->
  ret @@ go ResEnv.init psi

let rec elab_sig env =
  function
  | [] ->
    ret ()
  | dcl :: esig ->
    elab_decl env dcl >>= fun env' ->
    ambulando (Name.fresh ()) >>
    elab_sig env' esig

and elab_decl env =
  function
  | Make (name, scheme) ->
    hole Emp univ @@ fun ty ->
    hole Emp (Tm.up ty) @@ fun tm ->
    elab_scheme env (Tm.up ty) scheme >>
    ret @@ T.set name (ty, tm) env

  | Refine (name, e) ->
    begin
      match T.find name env with
      | Some (ty, tm) ->
        elab_term env (Tm.up ty, Tm.up tm) e >>
        ret env
      | None ->
        failwith "Refine"
    end

  | Debug ->
    dump_state Format.std_formatter "debug" >>
    ret env


and elab_scheme env tm scheme =
  elab_term env (univ, tm) scheme

and elab_term env (ty,tm) =
  function
  | Type ->
    let q = {ty0 = univ; ty1 = univ; tm0 = tm; tm1 = Tm.univ ~lvl:(Lvl.Const 0) ~kind:Kind.Kan} in
    active @@ Unify q

  | Pair (e0, e1) ->
    get_tele >>= fun psi ->
    let x = Name.fresh () in
    hole psi univ @@ fun tau0 ->
    hole (psi #< (x, Tm.up tau0)) univ @@ fun tau1x ->
    hole psi (Tm.up tau0) @@ fun tm0 ->
    let tau1 = Tm.subst (Tm.Sub (Tm.Id, tm0)) @@ Tm.close_var x 0 @@ Tm.up tau1x in
    hole psi tau1 @@ fun tm1 ->
    let sigma_ty = Tm.make @@ Tm.Sg (Tm.up tau0, Tm.bind x @@ Tm.up tau1x) in
    let pair = Tm.cons (Tm.up tm0) (Tm.up tm1) in
    active @@ Unify {ty0 = univ; ty1 = univ; tm0 = ty; tm1 = sigma_ty} >>
    active @@ Unify {ty0 = ty; tm0 = tm; ty1 = sigma_ty; tm1 = pair} >>
    elab_term env (Tm.up tau0, Tm.up tm0) e0 >>
    elab_term env (tau1, Tm.up tm1) e1

  | Lam (name, e) ->
    get_tele >>= fun psi ->

    let x = Name.named @@ Some name in

    hole psi univ @@ fun tau0 ->
    hole (psi #< (x, Tm.up tau0)) univ @@ fun tau1x ->
    hole (psi #< (x, Tm.up tau0)) (Tm.up tau1x) @@ fun bdyx ->

    let pi_ty = Tm.make @@ Tm.Pi (Tm.up tau0, Tm.bind x @@ Tm.up tau1x) in
    let lam_tm = Tm.make @@ Tm.Lam (Tm.bind x @@ Tm.up bdyx) in

    active @@ Unify {ty0 = univ; ty1 = univ; tm0 = ty; tm1 = pi_ty} >>
    active @@ Unify {ty0 = ty; ty1 = pi_ty; tm0 = tm; tm1 = lam_tm} >>

    in_scope x (P (Tm.up tau0)) @@
    elab_term env (Tm.up tau1x, Tm.up bdyx) e

  | Quo tmfam ->
    get_resolver >>= fun renv ->
    Format.eprintf "ty: %a; tm0 : %a; tm1 : %a@.@."
      (Tm.pp Pretty.Env.emp) ty
      (Tm.pp Pretty.Env.emp) tm
      (Tm.pp Pretty.Env.emp) (tmfam renv);
    active @@ Unify {ty0 = ty; ty1 = ty; tm0 = tm; tm1 = tmfam renv}

  | Hole ->
    ret ()

  | _ ->
    failwith "TODO: elab_term"


let script =
  [ Make ("foo", Type)
  ]


let test = elab_sig (T.init ~size:10) script
