open RedBasis
open Dev

include IxMonad.S

type ('i, 'o) move = ('i, 'o, unit) m

val run : ty -> (dev, dev) move -> tm

(** The names of these moves are not yet perfected. *)

val push_guess : (cell, dev) move
val pop_guess : (dev, cell) move
val push_cell : (dev, cell) move
val pop_cell : (cell, dev) move

val down : (dev, dev) move
val up : (dev, dev) move

val eval : 'a Tm.t -> ('i, 'i, Val.value) m
val evaluator : (dev, dev, (module Val.S)) m
val typechecker : (dev, dev, (module Typing.S)) m



(** an abstract type for values that need to be shifted as they descend under binders *)
type 'a frozen
val freeze : 'a -> ('i, 'i, 'a frozen) m
val defrost_tm : 'a Tm.t frozen -> ('i, 'i, 'a Tm.t) m
val defrost_sys : Tm.chk Tm.t Tm.system frozen -> ('i, 'i, Tm.chk Tm.t Tm.system) m
val defrost_rty : rty frozen -> ('i, 'i, rty) m


val get_hole : (dev, dev, DevCx.t * rty) m

val claim : string option -> rty -> (dev, dev) move
val claim_with : string option -> rty -> (Tm.inf Tm.t frozen -> (dev, dev) move) -> (dev, dev) move

(** When the cursor is at a [Hole ty], check the supplied [tm] against [ty];
    if it matches, then replace the hole with [Ret tm]. *)
val fill_hole : tm -> (dev, dev) move


(** When the cursor is at a {e pure} [Guess] cell, replace it with a [Let] cell. *)
val solve : (cell, cell) move


(** When the cursor is at a hole of dependent function type, replace it with
    a [Lam] cell and a hole underneath it. *)
val lambda : string option -> (dev, dev) move

val user_hole : string -> (dev, dev) move


