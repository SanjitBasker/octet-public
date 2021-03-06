open Notty
open Util

type label =
  | Keyword of string
  | Symbol of string
  | Number of string
  | Other of string

let get_regex file field =
  file
  |> Yojson.Basic.Util.member field
  |> Yojson.Basic.Util.to_string |> Str.regexp

let keyword_regex, symbol_regex =
  try
    let file = Yojson.Basic.from_file "config/syntax.json" in
    (get_regex file "keywords", get_regex file "symbols")
  with _ -> (Str.regexp "", Str.regexp "")

let color_of_string =
  let open Notty.A in
  function
  | "black" -> black
  | "red" -> red
  | "green" -> green
  | "yellow" -> yellow
  | "blue" -> blue
  | "magenta" -> magenta
  | "cyan" -> cyan
  | "white" -> white
  | "lightblack" -> lightblack
  | "lightred" -> lightred
  | "lightgreen" -> lightgreen
  | "lightyellow" -> lightyellow
  | "lightblue" -> lightblue
  | "lightmagenta" -> lightmagenta
  | "lightcyan" -> lightcyan
  | "lightwhite" -> lightwhite
  | _ -> blue

type colormode = {
  bg : A.color;
  keyword : A.color;
  symbol : A.color;
  number : A.color;
  other : A.color;
}

type colors = {
  cursor : colormode;
  hl : colormode;
  default : colormode;
}

let colormode_of_json j =
  let open Yojson.Basic.Util in
  let parse name = j |> member name |> to_string |> color_of_string in
  {
    bg = parse "background";
    keyword = parse "keyword";
    symbol = parse "symbol";
    number = parse "number";
    other = parse "other";
  }

let default_color_config =
  let open Notty.A in
  let defaultmode =
    {
      bg = black;
      keyword = yellow;
      symbol = red;
      number = green;
      other = white;
    }
  in
  {
    cursor = { defaultmode with bg = white };
    hl = { defaultmode with bg = blue };
    default = defaultmode;
  }

let color_config =
  try
    let open Yojson.Basic.Util in
    let file = Yojson.Basic.from_file "config/colors.json" in
    {
      cursor = file |> member "cursor" |> colormode_of_json;
      hl = file |> member "highlight" |> colormode_of_json;
      default = file |> member "standard" |> colormode_of_json;
    }
  with _ -> default_color_config

let tag_of_word w =
  if Str.string_match keyword_regex w 0 then Keyword w
  else if Str.string_match symbol_regex w 0 then Symbol w
  else
    match (int_of_string_opt w, float_of_string_opt w) with
    | None, None -> Other w
    | _ -> Number w

let rec insert_spaces l =
  match l with
  | [] -> []
  | [ h ] -> [ h ]
  | h :: t -> h :: " " :: insert_spaces t

let tag_of_string s =
  String.split_on_char ' ' s |> insert_spaces |> List.map tag_of_word

let char_tags_of_other w =
  let split = string_list_of_string w in
  List.map tag_of_word split

let char_tags_of_word w =
  match w with
  | Keyword w ->
      List.map (fun c -> Keyword c) @@ string_list_of_string w
  | Symbol w -> List.map (fun c -> Symbol c) @@ string_list_of_string w
  | Number w -> List.map (fun c -> Number c) @@ string_list_of_string w
  | Other w -> char_tags_of_other w

let char_tags_of_string s =
  tag_of_string s |> List.map char_tags_of_word |> List.flatten

let debug_aux l =
  match l with
  | Keyword w -> [ "K"; w ]
  | Symbol w -> [ "S"; w ]
  | Number w -> [ "N"; w ]
  | Other w -> [ "O"; w ]

let char_tags_of_string_verbose s =
  char_tags_of_string s |> List.map debug_aux |> List.flatten
  |> string_of_string_list

let label_to_image mode label =
  let background = mode.bg in
  let color, word =
    match label with
    | Keyword w -> (mode.keyword, w)
    | Symbol w -> (mode.symbol, w)
    | Number w -> (mode.number, w)
    | Other w -> (mode.other, w)
  in
  I.string A.(fg color ++ bg background) word

let label_to_image_hl_cursor hl cursor label =
  if cursor then label_to_image color_config.cursor label
  else if hl then label_to_image color_config.hl label
  else label_to_image color_config.default label

let image_of_string hl_opt cursor_opt s =
  let tagged = char_tags_of_string s in
  let imlist =
    match hl_opt with
    | None ->
        tagged
        |> List.mapi (fun i ->
               label_to_image_hl_cursor false (Some i = cursor_opt))
    | Some (st, en) ->
        tagged
        |> List.mapi (fun i ->
               label_to_image_hl_cursor
                 (i >= st && i <= en)
                 (cursor_opt = Some i))
  in
  imlist |> I.hcat

let make_line_numbers s h =
  Util.from s (s + h - 1)
  |> List.map (fun d ->
         I.string A.(bg black ++ st italic) (Printf.sprintf "% 3d " d))
  |> I.vcat

let crop_to ((width, height) : int * int) img_lst =
  let open Notty in
  let widthcropped =
    I.vcat
      (List.map
         (fun img -> I.hcrop 0 (I.width img - width) img)
         img_lst)
  in
  I.vcrop 0 (I.height widthcropped - height) widthcropped
