(*
 * Author: Kaustuv Chaudhuri <kaustuv.chaudhuri@inria.fr>
 * Copyright (C) 2013  Inria (Institut National de Recherche
 *                     en Informatique et en Automatique)
 * See LICENSE for licensing details.
 *)

open Base

type doc = Caml.Format.formatter -> unit

let string s : doc =
  fun out -> Caml.Format.pp_print_string out s

let string_as n s : doc =
  fun out -> Caml.Format.pp_print_as out n s

let cut : doc =
  fun out -> Caml.Format.pp_print_cut out ()

let (++) d1 d2 : doc =
  fun out -> d1 out ; d2 out

let pp out (doc : doc) = doc out

let to_string (doc : doc) =
  let buf = Buffer.create 19 in
  let out = Caml.Format.formatter_of_buffer buf in
  Caml.Format.pp_set_geometry out
    ~margin:Int.max_value
    ~max_indent:(Int.max_value - 1) ;
  doc out ;
  Caml.Format.pp_print_flush out () ;
  Buffer.contents buf

let pp_linear out (doc : doc) =
  Caml.Format.pp_print_as out 0 (to_string doc)

type wrapping = Transparent | Opaque [@@deriving equal]
type assoc = Left | Right | Non [@@deriving equal]

type exp =
  | Atom of doc
  | Wrap of wrapping * doc * exp * doc
  | Appl of int * bappl

and bappl =
  | Prefix of doc * exp
  | Postfix of doc * exp
  | Infix of doc * assoc * exp list

let rec ( >=? ) prec be = match be with
  | Appl (subprec, _) when prec >= subprec -> true
  | Wrap (Transparent, _, be, _) -> prec >=? be
  | _ -> false

let rec ( >? ) prec be = match be with
  | Appl (subprec, _) when prec > subprec -> true
  | Wrap (Transparent, _, be, _) -> prec >? be
  | _ -> false

let rec is_prefix = function
  | Appl (_, Prefix _) -> true
  | Wrap (Transparent, _, be, _) -> is_prefix be
  | _ -> false

let rec is_postfix = function
  | Appl (_, Postfix _) -> true
  | Wrap (Transparent, _, be, _) -> is_postfix be
  | _ -> false

let rec infix_incompat_for tasc pr asc = function
  | Appl (spr, (Prefix _ | Postfix _))
    when pr >= spr -> true
  | Appl (spr, Infix (_, sasc, _))
    when pr = spr && not (equal_assoc asc tasc && equal_assoc sasc tasc) -> true
  | Wrap (Transparent, _, be, _) ->
      infix_incompat_for tasc pr asc be
  | _ -> false

type dinfo = PRE of int | POST of int | NVM

let rec reprec e =
  begin match e with
  | Atom _ -> (e, NVM)
  | Appl (p, Infix (d, asc, es)) ->
      let es = List.map ~f:(fun e -> fst (reprec e)) es in
      (Appl (p, Infix (d, asc, es)), NVM)
  | Appl (p, Prefix (d, e)) ->
      begin
        let (e, di) = reprec e in
        let p = begin match di with
          | PRE q -> min p q
          | _ -> p
        end in
        (Appl (p, Prefix (d, e)), PRE p)
      end
  | Appl (p, Postfix (d, e)) ->
      begin
        let (e, di) = reprec e in
        let p = begin
          match di with
          | POST q -> min p q
          | _ -> p
        end in
        (Appl (p, Postfix (d, e)), POST p)
      end
  | Wrap (wt, b, e, a) ->
      let (e, di) = reprec e in
      let di = begin match wt with
        | Transparent -> di
        | Opaque -> NVM
      end in
      (Wrap (wt, b, e, a), di)
  end

let delimit ?(cond=true) ~ld ~rd d =
  if not cond then d else ld ++ d ++ rd

let rec bracket ~(ld:doc) ~(rd:doc) = function
  | Atom d -> d
  | Wrap (_, ld1, be, rd1) ->
      delimit ~ld:ld1 ~rd:rd1 (bracket ~ld ~rd be)
  | Appl (prec, appl) -> begin
      match appl with
      | Prefix (oprep, be) ->
          let opd = bracket ~ld ~rd be in
          let cond = prec >? be && not (is_prefix be) in
          oprep ++ (delimit opd ~ld ~rd ~cond)
      | Postfix (oprep, be) ->
          let opd = bracket ~ld ~rd be in
          let cond = prec >? be && not (is_postfix be) in
          (delimit opd ~ld ~rd ~cond) ++ oprep
      | Infix (oprep, asc, l :: es) ->
          let ms, r = match List.rev es with
            | r :: rms -> List.rev rms, r
            | [] -> invalid_arg "bracket"
          in
          let l = delimit (bracket ~ld ~rd l) ~ld ~rd
              ~cond:(prec >? l
                     || infix_incompat_for Left prec asc l) in
          let r = delimit (bracket ~ld ~rd r) ~ld ~rd
              ~cond:(prec >? r
                     || infix_incompat_for Right prec asc r) in
          let ms = List.map
              ~f:begin fun e ->
                [oprep ; delimit (bracket ~ld ~rd e) ~ld ~rd ~cond:(prec >=? e)]
              end ms in
          let ms = List.concat ms in
          fun out -> begin
              Caml.Format.pp_open_hovbox out 0 ;
              l out ;
              List.iter ~f:(fun m -> m out) ms ;
              oprep out ; r out ;
              Caml.Format.pp_close_box out ()
            end
      | Infix (_, _, []) -> invalid_arg "bracket"
    end

let bracket ?(ld = string "(") ?(rd = string ")") e =
  let (e, _) = reprec e in
  bracket ~ld ~rd e
