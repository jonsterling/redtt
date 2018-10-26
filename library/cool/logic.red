import prelude
import data.void
import data.bool
import paths.bool
import basics.hedberg

def no-double-neg-elim (f : (A : type) → stable A) : void = 
  let f2 = f bool in 

  -- transport along the path induced from `not` by univalence
  let tf2 = coe 0 1 f2 in λ i → stable (not/path i) in

  -- transporting a dependent function produces a path to the original
  let apdf : path _ tf2 f2 = apd^1 _ stable f _ _ not/path in

  -- tf2 is equal to a composition of transporting the argument backwards along `neg (neg (symm not/path))`...
  let inner(u : neg (neg bool)) : neg (neg bool) = coe 0 1 u in λ i → neg (neg (symm^1 type not/path i)) in

  -- ... and then `f2` applied to result forwards along `not/path`
  -- however transporting along a univalence-produced path equals applying the original iso
  -- thus `tf2 u = not (f2 (inner u)`

  -- since `neg A` is a prop
  let inner→u(u : neg (neg bool)) : path _ u (inner u) = neg/prop (neg bool) u (inner u) in

  -- lift this to a path into `tf2`
  let notf2→tf2(u : neg (neg bool)) : path _ (not (f2 u)) (tf2 u) = λ i → not (f2 (inner→u u i)) in

  -- and compose paths to obtain a contradictory path
  let contra(u : neg (neg bool)) : path _ (not (f2 u)) (f2 u) = trans _ (notf2→tf2 u) (λ i → apdf i u) in 

  let dne : neg (neg bool) = (λ negb → negb tt) in
  not/neg (f2 dne) (contra dne) 

def no-excluded-middle (g : (A : type) → dec A) : void = 
  no-double-neg-elim (λ A → dec→stable A (g A)) 
