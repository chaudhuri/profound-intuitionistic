(*
 * Author: Kaustuv Chaudhuri <kaustuv.chaudhuri@inria.fr>
 * Copyright (C) 2021  Inria (Institut National de Recherche
 *                     en Informatique et en Automatique)
 * See LICENSE for licensing details.
 *)

open! Util

type ty =
  | Basic of ident
  | Arrow of ty * ty
  | Tyvar of {id : int ; mutable subst : ty option}

let rec ty_norm = function
  | Tyvar { subst = Some ty ; _ } -> ty_norm ty
  | ty -> ty

let rec ty_to_exp ty =
  match ty with
  | Basic a -> Doc.(Atom (String a))
  | Arrow (ta, tb) ->
      Doc.(Appl (1, Infix (String " -> ", Right,
                           [ty_to_exp ta ; ty_to_exp tb])))
  | Tyvar v -> begin
      match v.subst with
      | None ->
          let rep = "'a" ^ string_of_int v.id in
          Doc.(Atom (String rep))
      | Some ty -> ty_to_exp ty
    end

let ty_to_string ty =
  ty_to_exp ty |> Doc.bracket |> Doc.lin_doc

module K = struct
  let next_internal =
    let count = ref 0 in
    fun hint -> incr count ;
      Printf.sprintf {|#%s@%d#|} hint !count

  let k_all = next_internal "forall"
  let k_ex  = next_internal "exists"
  let k_and = next_internal "and"
  let k_top = next_internal "top"
  let k_or  = next_internal "or"
  let k_bot = next_internal "bot"
  let k_imp = next_internal "imp"
  let k_eq  = next_internal "eq"
  let k_pos_int = next_internal "posint"
  let k_neg_int = next_internal "negint"
  let ty_o  = Basic (next_internal "o")
  let ty_i  = Basic (next_internal "i")
  (* let ty_o = Basic "o" *)
  (* let ty_i = Basic "i" *)
end

type poly_ty = {nvars : int ; ty : ty}

let global_sig : poly_ty IdMap.t =
  let vnum n = Tyvar {id = n ; subst = None} in
  let binds = [
    K.k_all, {nvars = 1 ;
            ty = Arrow (Arrow (vnum 0, K.ty_o), K.ty_o)} ;
    K.k_ex, {nvars = 1 ;
           ty = Arrow (Arrow (vnum 0, K.ty_o), K.ty_o)} ;
    K.k_and, {nvars = 0 ; ty = Arrow (K.ty_o, Arrow (K.ty_o, K.ty_o))} ;
    K.k_top, {nvars = 0 ; ty = K.ty_o} ;
    K.k_or,  {nvars = 0 ; ty = Arrow (K.ty_o, Arrow (K.ty_o, K.ty_o))} ;
    K.k_bot, {nvars = 0 ; ty = K.ty_o} ;
    K.k_imp, {nvars = 0 ; ty = Arrow (K.ty_o, Arrow (K.ty_o, K.ty_o))} ;
    K.k_eq,  {nvars = 1 ;
            ty = Arrow (vnum 0, Arrow (vnum 0, K.ty_o))} ;
    K.k_pos_int, {nvars = 0 ; ty = Arrow (K.ty_o, Arrow (K.ty_o, K.ty_o))} ;
    K.k_neg_int, {nvars = 0 ; ty = Arrow (K.ty_o, Arrow (K.ty_o, K.ty_o))} ;
  ] |> List.to_seq in
  IdMap.add_seq binds IdMap.empty

let lookup k local_sig =
  match IdMap.find k local_sig with
  | ty -> ty
  | exception Not_found ->
      IdMap.find k global_sig

(** Untyped terms *)
module U = struct
  type term =
    | Idx of int
    | Var of ident
    | Kon of ident * ty option
    | App of term * term
    | Abs of ident * ty option * term
end

(** Typed and normalized terms *)
module T = struct
  type term =
    | Abs of {var : ident ; body : term}
    | App of {head : head ; spine : spine}

  and head =
    | Const of ident * ty
    | Index of int

  and spine = term list

  type sub =
    | Shift of int
    | Dot of sub * term
end

type typed_var = {
  var : ident ;
  ty : ty
}

type tycx = {
  linear : typed_var list ;
  used : IdSet.t ;
}

let empty = {
  linear = [] ;
  used = IdSet.empty ;
}

let[@inline] salt v k =
  if k = 0 then v else v ^ "_" ^ string_of_int k

let with_var ?(fresh = false) tycx vty go =
  let rec freshen v k =
    let vk = salt v k in
    if IdSet.mem vk tycx.used then freshen v (k + 1) else vk
  in
  let var = if fresh then freshen vty.var 0 else vty.var in
  let used = IdSet.add var tycx.used in
  let vty = { vty with var } in
  let linear = vty :: tycx.linear in
  go vty {linear ; used}

let last_var tycx = List.hd tycx.linear

let last tycx =
  match tycx.linear with
  | [] -> raise Not_found
  | tv :: linear ->
      (tv, { linear ; used = IdSet.remove tv.var tycx.used })

let last_opt tycx =
  match tycx.linear with
  | [] -> None
  | tv :: linear ->
      Some (tv, { linear ; used = IdSet.remove tv.var tycx.used })

type 'a incx = {
  tycx : tycx ;
  data : 'a ;
 }

let ( |@ ) f th = { th with data = f }
