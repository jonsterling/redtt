type var = Thin.t

type 'a bnd = B of 'a

type chk = [`Chk]
type inf = [`Inf]

type info = Lexing.position * Lexing.position

type _ f =
  | Var : var -> inf f
  | Car : inf t -> inf f
  | Cdr : inf t -> inf f
  | App : inf t * chk t -> inf f
  | Down : {ty : chk t; tm : chk t} -> inf f
  | Coe : {tag : Cube.t; dim0 : chk t; dim1 : chk t; ty : chk t bnd; tm : chk t} -> inf f
  | HCom : {tag : Cube.t; dim0 : chk t; dim1 : chk t; ty : chk t; cap : chk t; sys : chk t bnd system} -> inf f
  | Com : {tag : Cube.t; dim0 : chk t; dim1 : chk t; ty : chk t bnd; cap : chk t; sys : chk t bnd system} -> inf f  

  | Up : inf t -> chk f

  | Univ : Lvl.t -> chk f
  | Pi : chk t * chk t bnd -> chk f
  | Sg : chk t * chk t bnd -> chk f
  | Ext : chk t * chk t system -> chk f
  | Interval : Cube.t -> chk f

  | Lam : chk t bnd -> chk f
  | Cons : chk t * chk t -> chk f
  | Dim0 : chk f
  | Dim1 : chk f

and 'a node = {info : info option; con : 'a f; thin : Thin.t}
and 'a t = 'a node
and 'a tube = chk t * chk t * 'a option
and 'a system = 'a tube list

let into tf = {info = None; con = tf; thin = Thin.id}
let into_info info tf = {info = Some info; con = tf; thin = Thin.id}
let info node = node.info

let thin : type a. Thin.t -> a t -> a t = 
  fun th {info; con; thin} ->
    {info; con; thin = Thin.cmp thin th}

let thin_bnd : type a. Thin.t -> a t bnd -> a t bnd = 
  fun th (B t) ->
    B (thin (Thin.skip th) t)


let thin_tube : type a b. Thin.t -> b t tube -> b t tube = 
  fun th (td0, td1, tm) ->
    (thin th td0, thin th td1, Option.map (thin th) tm)

let thin_btube : type a b. Thin.t -> b t bnd tube -> b t bnd tube = 
  fun th (td0, td1, tm) ->
    (thin th td0, thin th td1, Option.map (thin_bnd th) tm)

let thin_bsys : type a. Thin.t -> a t bnd system -> a t bnd system = 
  fun th ->
    List.map (thin_btube th)

let thin_sys : type a. Thin.t -> a t system -> a t system = 
  fun th ->
    List.map (thin_tube th)


let rec thin_f : type a. Thin.t -> a f -> a f = 
  fun th tf ->
    match tf with 
    | Var g ->
      Var (Thin.cmp g th)

    | Car t ->
      Car (thin th t)

    | Cdr t -> 
      Cdr (thin th t)

    | App (t1, t2) ->
      App (thin th t1, thin th t2)

    | Down {ty; tm} ->
      Down {ty = thin th ty; tm = thin th tm}

    | Coe info ->
      Coe {tag = info.tag; dim0 = thin th info.dim0; dim1 = thin th info.dim1; ty = thin_bnd th info.ty; tm = thin th info.tm}

    | HCom info ->
      HCom {tag = info.tag; dim0 = thin th info.dim0; dim1 = thin th info.dim1; ty = thin th info.ty; cap = thin th info.cap; sys = thin_bsys th info.sys}

    | Com info ->
      Com {tag = info.tag; dim0 = thin th info.dim0; dim1 = thin th info.dim1; ty = thin_bnd th info.ty; cap = thin th info.cap; sys = thin_bsys th info.sys}

    | Up t ->
      Up (thin th t)

    | Univ lvl ->
      tf

    | Pi (dom, cod) ->
      Pi (thin th dom, thin_bnd th cod)

    | Sg (dom, cod) ->
      Sg (thin th dom, thin_bnd th cod)

    | Ext (ty, sys) ->
      Ext (thin th ty, thin_sys th sys)

    | Interval _ ->
      tf

    | Lam bdy ->
      Lam (thin_bnd th bdy)

    | Cons (t1, t2) ->
      Cons (thin th t1, thin th t2)

    | Dim0 ->
      tf

    | Dim1 ->
      tf


let out node = thin_f node.thin node.con

(* TODO incorrect!!! *)
let eq t1 t2 =
  t1 = t2

module Pretty =
struct
  module Env :
  sig
    type t
    val emp : t
    val var : int -> t -> string
    val bind : t -> string * t
  end =
  struct
    type t = int * string list

    let emp = 0, []
    let var i (_, xs) = List.nth xs i
    let bind (i, xs) =
      let x = "x" ^ string_of_int i in
      x, (i + 1, x :: xs)
  end

  let pp : type a. Env.t -> Format.formatter -> a t -> unit = 
    fun _ _ -> failwith "pp"
end