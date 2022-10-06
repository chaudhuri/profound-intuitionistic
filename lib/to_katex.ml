(*
 * Author: Kaustuv Chaudhuri <kaustuv.chaudhuri@inria.fr>
 * Copyright (C) 2022  Inria (Institut National de Recherche
 *                     en Informatique et en Automatique)
 * See LICENSE for licensing details.
 *)

(** Output suitable for processing with katex

    https://katex.org *)

open Base

open! Util
open! Types
open! Term
open! Form4

let rep_arr : Doc.doc = Doc.(string_as 2 {|\to|} ++ cut)

let texify id =
  match String.split ~on:'_' id |>
        List.filter ~f:(fun s -> not @@ String.is_empty s) |>
        List.rev with
  | [] -> id
  | last :: rev_rest ->
      List.fold_left ~f:begin fun n i ->
        i ^ "_{" ^ n ^ "}"
      end ~init:last rev_rest

let tex_string str = Doc.string_as (String.length str) (texify str)

let rec ty_to_exp ty =
  match ty with
  | Ty.Basic a ->
      let rep = if Ident.equal a Ty.k_o then "o" else (Ident.to_string a) in
      let len = String.length rep in
      let rep = "\\mathsf{" ^ texify rep ^ "}" in
      Doc.(Atom (string_as len rep))
  | Ty.Arrow (ta, tb) ->
      Doc.(Appl (1, Infix (rep_arr, Right,
                           [ty_to_exp ta ; ty_to_exp tb])))
  | Ty.Var v -> begin
      match v.subst with
      | None -> Doc.(Atom (string_as 1 "\\_"))
      | Some ty -> ty_to_exp ty
    end

let pp_ty out ty = ty_to_exp ty |> Doc.bracket |> Doc.pp_linear out

let rep_lambda var : Doc.doc =
  Caml.Format.dprintf {|\lambda{%s}.\,@,|} var
let rep_appl : Doc.doc = Caml.Format.dprintf {|\,@,|}

let fresh_id =
  let count = ref 0 in
  fun () -> Int.incr count ; !count

let rec termx_to_exp_ ~cx t =
  match t with
  | T.Abs { var ; body } ->
      with_var cx { var ; ty = K.ty_any } begin fun vty cx ->
        Doc.(Appl (1, Prefix (rep_lambda (Ident.to_string vty.var), termx_to_exp_  ~cx body)))
      end
  | T.App { head ; spine = [] } ->
      head_to_exp_ ~cx head
  | T.App { head ; spine } ->
      let head = head_to_exp_ ~cx head in
      let spine = List.map ~f:(termx_to_exp_ ~cx) spine in
      Doc.(Appl (100, Infix (rep_appl, Left, (head :: spine))))

and head_to_exp_ ~cx head =
  match head with
  | T.Const (k, _) ->
      let k = Ident.to_string k in
      Doc.(Atom (string_as 0 "\\mathsf{" ++ tex_string k ++ string_as 0 "}"))
  | T.Index n ->
      let v = Ident.to_string (List.nth_exn cx.linear n).var in
      Doc.(Atom (tex_string v))

let termx_to_exp tx =
  Doc.(Wrap (Transparent,
             string_as 0 (Printf.sprintf "\\htmlId{t%d}{" @@ fresh_id ()),
             termx_to_exp_ ~cx:tx.tycx tx.data,
             string_as 0 "}"))
let pp_termx out tx = termx_to_exp tx |> Doc.bracket |> Doc.pp_linear out

let rep_eq  : Doc.doc = Caml.Format.dprintf {|\mathbin{\doteq}@,|}
let rep_and : Doc.doc = Caml.Format.dprintf {|\mathbin{\land}@,|}
let rep_top : Doc.doc = Caml.Format.dprintf {|\top|}
let rep_or  : Doc.doc = Caml.Format.dprintf {|\mathbin{\lor}@,|}
let rep_bot : Doc.doc = Caml.Format.dprintf {|\bot|}
let rep_imp : Doc.doc = Caml.Format.dprintf {|\mathbin{\Rightarrow}@,|}
let rep_forall vty : Doc.doc =
  let v = Ident.to_string vty.var in
  Caml.Format.dprintf {|\forall{%t}{:}%a.\,@,|}
    (Doc.string_as (String.length v) (texify v))
    pp_ty vty.ty
let rep_exists vty : Doc.doc  =
  let v = Ident.to_string vty.var in
  Caml.Format.dprintf {|\exists{%t}{:}%a.\,@,|}
    (Doc.string_as (String.length v) (texify v))
    pp_ty vty.ty

let dir_to_string (d : dir) =
  match d with
  | L -> "l"
  | R -> "r"
  | D -> "d"
  | I x -> "i(" ^ (Ident.to_string x) ^ ")"
let path_to_string path =
  path
  |> Q.to_list
  |> List.map ~f:dir_to_string
  |> String.concat ~sep:";"

let wrap path doc =
  let lbra =
    Printf.sprintf "\\htmlId{f%d}{\\htmlData{path=%s}{"
      (fresh_id ())
      (path_to_string path)
  in
  Doc.(Wrap (Transparent, string_as 0 lbra, doc, string_as 0 "}}"))

let rec formx_to_exp_ ~cx (path : path) f =
  match expose f with
  | Atom a -> termx_to_exp_ ~cx a |> wrap path
  | Eq (s, t, _) ->
      let s = termx_to_exp_ ~cx s in
      let t = termx_to_exp_ ~cx t in
      Doc.(Appl (40, Infix (rep_eq, Non, [s ; t]))) |> wrap path
  | And (a, b) ->
      let a = formx_to_exp_ ~cx (Q.snoc path L) a in
      let b = formx_to_exp_ ~cx (Q.snoc path R) b in
      Doc.(Appl (30, Infix (rep_and, Right, [a ; b]))) |> wrap path
  | Top -> Doc.(Atom rep_top) |> wrap path
  | Or (a, b) ->
      let a = formx_to_exp_ ~cx (Q.snoc path L) a in
      let b = formx_to_exp_ ~cx (Q.snoc path R) b in
      Doc.(Appl (20, Infix (rep_or, Right, [a ; b]))) |> wrap path
  | Bot -> Doc.(Atom rep_bot) |> wrap path
  | Imp (a, b) ->
      let a = formx_to_exp_ ~cx (Q.snoc path L) a in
      let b = formx_to_exp_ ~cx (Q.snoc path R) b in
      Doc.(Appl (10, Infix (rep_imp, Right, [a ; b]))) |> wrap path
  | Forall (vty, b) ->
      with_var cx vty begin fun vty cx ->
        let b = formx_to_exp_ ~cx (Q.snoc path (I vty.var)) b in
        Doc.(Appl (5, Prefix (rep_forall vty, b))) |> wrap path
      end
  | Exists (vty, b) ->
      with_var cx vty begin fun vty cx ->
        let b = formx_to_exp_ ~cx (Q.snoc path (I vty.var)) b in
        Doc.(Appl (5, Prefix (rep_exists vty, b))) |> wrap path
      end
  | Mdata (md, _, f) -> begin
      let doc = formx_to_exp_ ~cx path f in
      match md with
      | T.App { head = Const ({base = "src" ; _}, _) ; _ } ->
          Doc.(Wrap (Transparent,
                     string_as 0 "\\lnsrc{",
                     doc, string_as 0 "}"))
      | T.App { head = Const ({base = "dest" ; _}, _) ; _ } ->
          Doc.(Wrap (Transparent,
                     string_as 0 "\\lndest{",
                     doc, string_as 0 "}"))
      | _ -> assert false
    end

let formx_to_exp fx = formx_to_exp_ ~cx:fx.tycx Q.empty fx.data

let formx_to_sout fx =
  let sob = Caml.Format.make_symbolic_output_buffer () in
  let sout = Caml.Format.formatter_of_symbolic_output_buffer sob in
  Caml.Format.pp_set_geometry sout ~margin:120 ~max_indent:119 ;
  formx_to_exp fx |> Doc.bracket |> Doc.pp sout ;
  Caml.Format.pp_print_flush sout () ;
  Caml.Format.flush_symbolic_output_buffer sob

let formx_to_string fx =
  let buf = Buffer.create 19 in
  formx_to_sout fx |>
  List.iter ~f:Caml.Format.(fun item ->
      match item with
      | Output_newline -> Buffer.add_string buf "\\htmlClass{brk}{}"
      | Output_string str -> Buffer.add_string buf str
      | ( Output_spaces n | Output_indent n ) when n > 0 ->
          Buffer.add_string buf "\\htmlData{spc=" ;
          Buffer.add_string buf (Int.to_string n) ;
          Buffer.add_string buf "}{}"
      | _ -> ()
    ) ;
  Buffer.contents buf

let pp_formx out fx = formx_to_exp fx |> Doc.bracket |> Doc.pp_linear out

let pp_sigma out sg =
  Caml.Format.pp_open_vbox out 0 ; begin
    Set.iter ~f:begin fun i ->
      if Set.mem sigma0.basics i then () else
        Caml.Format.fprintf out {|%s : \mathsf{type}.@,|} (Ident.to_string i)
    end sg.basics ;
    Map.iteri ~f:begin fun ~key:k ~data:ty ->
      if Map.mem sigma0.consts k then () else
        Caml.Format.fprintf out {|%s : %a.@,|} (Ident.to_string k) pp_ty (thaw_ty ty)
    end sg.consts
  end ; Caml.Format.pp_close_box out ()

let pp_path out (path : path) =
  Q.to_list path |>
  Caml.Format.pp_print_list
    ~pp_sep:(fun out () -> Caml.Format.pp_print_string out ", ")
    Paths.Dir.(fun out -> function
        | L -> Caml.Format.pp_print_string out "l"
        | R -> Caml.Format.pp_print_string out "r"
        | D -> Caml.Format.pp_print_string out "d"
        | I x ->
            Caml.Format.pp_print_string out "i " ;
            Caml.Format.pp_print_string out (Ident.to_string x)) out

let pp_deriv out (sg, deriv) =
  pp_sigma out sg ;
  Caml.Format.fprintf out "%a@." pp_formx deriv.Cos.top ;
  List.iter ~f:begin fun (_, rule, concl) ->
    Caml.Format.fprintf out "%a :: %a@."
      pp_path rule.Cos.path
      Cos.pp_rule_name rule.Cos.name ;
    Caml.Format.fprintf out "%a@." pp_formx concl ;
  end deriv.middle

let pp_header _out () = ()
let pp_footer _out () = ()
let pp_comment out str =
  Caml.Format.( pp_print_string out "% " ;
           pp_print_string out str ;
           pp_print_newline out () )

let name = "katex"
let files _ = invalid_arg "To.Katex.files"
let build () = invalid_arg "To.Katex.build"
