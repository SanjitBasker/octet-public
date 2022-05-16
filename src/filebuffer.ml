module Make (LineBuffer : Obuffer.MUT_BUFFER) : Obuffer.MUT_FILEBUFFER =
struct
  type t = {
    mutable front : LineBuffer.t list;
    mutable back : LineBuffer.t list;
    mutable cursor_pos : int;
    mutable cursor_pos_cache : int;
    mutable desc : string;
    mutable cursor_line : int;
    mark_line : int;
    mark_pos : int;
    mark_active : bool;
  }
  (** AF: buffers for the lines in the text file before and including
      the line with the cursor are in [front], in reverse order; buffers
      for lines after the cursor are in [back]; [cursor_pos] and
      [cursor_pos_cache] track the horizontal position of the cursor
      along the current and past lines. [desc] is the path to which file
      buffer_contents will be written.

      RI: [cursor_pos_cache >= cursor_pos]. [h <> \[\]]. no line buffers
      contain the character ['\n']. *)

  let empty () =
    {
      front = [ LineBuffer.make "" 3 ];
      back = [];
      cursor_pos = 0;
      cursor_pos_cache = 0;
      desc = "data/Empty Buffer";
      cursor_line = 0;
      mark_line = 0;
      mark_pos = 0;
      mark_active = false;
    }

  let insert_char fb c =
    match fb.front with
    | h :: _ ->
        LineBuffer.move_to h fb.cursor_pos_cache;
        LineBuffer.insert h c;
        fb.cursor_pos <- fb.cursor_pos + 1;
        fb.cursor_pos_cache <- fb.cursor_pos;
        fb
    | [] -> failwith "no front buffer?"

  let insert_newline fb =
    match fb.front with
    | [] -> failwith "no front buffer?"
    | h :: t ->
        let s = LineBuffer.to_string h in
        let l =
          List.map
            (fun s -> LineBuffer.make s 3)
            (Util.split_at_n s fb.cursor_pos)
        in
        fb.front <- List.rev_append l t;
        fb.cursor_line <- fb.cursor_line + 1;
        fb.cursor_pos <- 0;
        fb.cursor_pos_cache <- 0;
        fb

  let mv_up fb =
    match fb.front with
    | [] -> failwith "no front buffer?"
    | [ _ ] -> fb
    | h1 :: h2 :: t ->
        LineBuffer.move_to h2 fb.cursor_pos_cache;
        fb.cursor_line <- fb.cursor_line - 1;
        fb.cursor_pos <-
          min fb.cursor_pos_cache (LineBuffer.content_size h2);
        fb.front <- h2 :: t;
        fb.back <- h1 :: fb.back;
        fb

  let mv_down fb =
    match fb.back with
    | [] -> fb
    | h :: t ->
        LineBuffer.move_to h fb.cursor_pos_cache;
        fb.cursor_line <- fb.cursor_line + 1;
        fb.cursor_pos <-
          min fb.cursor_pos_cache (LineBuffer.content_size h);
        fb.front <- h :: fb.front;
        fb.back <- t;
        fb

  let mv_left fb =
    match fb.front with
    | [] -> failwith "no front buffer?"
    | h :: _ ->
        let pos = max 0 (fb.cursor_pos - 1) in
        LineBuffer.move_to h pos;
        fb.cursor_pos <- pos;
        fb.cursor_pos_cache <- pos;
        fb

  let mv_right fb =
    match fb.front with
    | [] -> failwith "no front buffer?"
    | h :: _ ->
        let pos = min (LineBuffer.content_size h) (fb.cursor_pos + 1) in
        LineBuffer.move_to h pos;
        fb.cursor_pos <- pos;
        fb.cursor_pos_cache <- pos;
        fb

  let delete fb =
    begin
      match fb.front with
      | [] -> failwith "no front buffer?"
      | h1 :: h2 :: t when fb.cursor_pos = 0 ->
          let prev_line = LineBuffer.to_string h2 in
          let new_line = prev_line ^ LineBuffer.to_string h1 in
          let new_buf =
            LineBuffer.make new_line (2 * String.length new_line)
          in
          fb.front <- new_buf :: t;
          LineBuffer.move_to new_buf (String.length prev_line);
          fb.cursor_line <- fb.cursor_line - 1;
          fb.cursor_pos <- String.length prev_line;
          fb.cursor_pos_cache <- String.length prev_line
      | h :: _ ->
          LineBuffer.delete h;
          fb.cursor_pos <- max 0 (fb.cursor_pos - 1);
          fb.cursor_pos_cache <- max 0 (fb.cursor_pos_cache - 1)
    end;
    fb

  let buffer_contents fb =
    List.rev_append fb.back fb.front (* line buffers in reverse order *)
    |> List.rev_map LineBuffer.to_string

  let to_string fb = buffer_contents fb |> String.concat "\n"

  let from_file (file_name : string) =
    let ans = empty () in
    let line_list =
      Util.read_file file_name
      |> String.split_on_char '\n'
      |> List.map (fun s -> LineBuffer.make s 80)
    in
    match line_list with
    | [] -> ans
    | [ _ ] -> { ans with front = line_list }
    | h :: t -> { ans with front = [ h ]; back = t; desc = file_name }

  let write_to_file buffer =
    let out_channel = open_out buffer.desc in
    Printf.fprintf out_channel "%s\n" (to_string buffer);
    close_out out_channel

  let ocaml_format (fb : t) =
    let temp_path = "data/_temp.autoformat" in
    let out_channel = open_out temp_path in
    Printf.fprintf out_channel "%s\n" (to_string fb) |> ignore;
    close_out out_channel;
    Sys.command ("ocamlformat --inplace " ^ temp_path) |> ignore;
    let new_buffer = from_file temp_path in
    Sys.command ("rm " ^ temp_path) |> ignore;
    { new_buffer with desc = fb.desc }

  let rec paste_from_clipboard (buffer : t) =
    let temp_path = "data/_temp.clipboard" in
    Sys.command ("rm -rf " ^ temp_path) |> ignore;
    Sys.command ("touch " ^ temp_path) |> ignore;
    Sys.command ("pbpaste > " ^ temp_path) |> ignore;
    let s = Util.read_file temp_path in
    let num_of_char = String.length s in
    let clst =
      List.init num_of_char (fun i ->
          if i < num_of_char then String.get s i else '_')
    in
    Sys.command ("rm " ^ temp_path) |> ignore;
    insert_stream buffer clst

  and insert_stream (buffer : t) (lst : char list) =
    match lst with
    | [] -> buffer
    | '\n' :: t -> insert_stream (insert_newline buffer) t
    | h :: t -> insert_stream (insert_char buffer h) t

  let mv_cursor (buffer : t) direxn =
    match direxn with
    | `Up -> mv_up buffer
    | `Down -> mv_down buffer
    | `Left -> mv_left buffer
    | `Right -> mv_right buffer

  open Notty
  open Notty.Infix

  let cursor_icon = "⚛"

  let cursor_image width =
    I.void width 1 <|> I.string A.(bg red ++ st blink) cursor_icon

  let toggle_mark (buffer : t) =
    {
      buffer with
      mark_active = not buffer.mark_active;
      mark_line = buffer.cursor_line;
      mark_pos = buffer.cursor_pos;
    }

  let modeline_to_image (buffer : t) (width : int) =
    I.string
      A.(fg black ++ bg white)
      (buffer.desc ^ "  Cursor Line: "
      ^ string_of_int buffer.cursor_line
      ^ "  Col: "
      ^ string_of_int buffer.cursor_pos
      ^ " Mark Line: "
      ^ string_of_int buffer.mark_line
      ^ "  Col: "
      ^ string_of_int buffer.mark_pos)
    </> I.char A.(fg black ++ bg white) ' ' width 1

  let add_cursor (line : image) (cursor_pos : int) =
    cursor_image cursor_pos </> line

  let render_unselected (line : string) (active : bool) : image =
    I.string
      (if active then A.(fg lightwhite ++ bg lightblack) else A.empty)
      line

  let render_selected (line : string) : image =
    I.string A.(bg lightblue) line

  let render_beginning_selected
      (line : string)
      (pos : int)
      (active : bool) : image =
    let parts = Util.split_at_n line pos in
    render_selected (List.nth parts 0)
    <|> render_unselected (List.nth parts 1) active

  let render_end_selected (line : string) (pos : int) (active : bool) :
      image =
    let parts = Util.split_at_n line pos in
    render_unselected (List.nth parts 0) active
    <|> render_selected (List.nth parts 1)

  let render_selected_in_line
      (line : string)
      (s : int)
      (e : int)
      (active : bool) : image =
    let parts = Util.split_at_n line e in
    render_end_selected (List.nth parts 0) s active
    <|> render_unselected (List.nth parts 1) active

  let render_line_without_cursor
      (buffer : t)
      (absolute_line : int)
      (line : string)
      (active : bool) =
    if buffer.mark_active then
      let min_select = min buffer.cursor_line buffer.mark_line in
      let max_select = max buffer.cursor_line buffer.mark_line in
      let min_select_pos = min buffer.cursor_pos buffer.mark_pos in
      let max_select_pos = max buffer.cursor_pos buffer.mark_pos in
      let start_pos =
        if buffer.cursor_line < buffer.mark_line then buffer.cursor_pos
        else buffer.mark_pos
      in
      let end_pos =
        if buffer.cursor_line > buffer.mark_line then buffer.cursor_pos
        else buffer.mark_pos
      in
      if min_select = max_select && absolute_line = min_select then
        (* one line *)
        render_selected_in_line line min_select_pos max_select_pos
          active
      else if absolute_line < min_select then
        render_unselected line active
      else if absolute_line > max_select then
        render_unselected line active
      else if absolute_line = min_select then
        render_end_selected line start_pos active
      else if absolute_line = max_select then
        render_beginning_selected line end_pos active
      else render_selected line
    else render_unselected line active

  let render_line
      (buffer : t)
      (top_line : int)
      (show_cursor : bool)
      (i : int)
      (elt : string) =
    let absolute_location = i + top_line in
    if absolute_location = buffer.cursor_line && show_cursor then
      add_cursor
        (render_line_without_cursor buffer absolute_location elt
           show_cursor)
        buffer.cursor_pos
    else
      render_line_without_cursor buffer absolute_location elt
        show_cursor

  let _ = render_line

  let get_cursor_opt buffer show_cursor line_num =
    if not show_cursor then None
    else if buffer.cursor_line = line_num then Some buffer.cursor_pos
    else None

  let compute_hl_bounds buf =
    match
      (buf.mark_line < buf.cursor_line, buf.mark_line > buf.cursor_line)
    with
    | false, true ->
        (buf.cursor_line, buf.cursor_pos, buf.mark_line, buf.mark_pos)
    | true, false ->
        (buf.mark_line, buf.mark_pos, buf.cursor_line, buf.cursor_pos)
    | false, false ->
        ( buf.mark_line,
          min buf.mark_pos buf.cursor_pos,
          buf.mark_line,
          max buf.mark_pos buf.cursor_pos )
    | _ -> failwith "RI violated"

  let get_hl_opt
      buffer
      width
      (start_line, start_pos, end_line, end_pos)
      line =
    if not buffer.mark_active then None
    else if start_line = end_line && start_line = line then
      Some (start_pos, end_pos)
    else if start_line = line then Some (start_pos, width)
    else if end_line = line then Some (0, end_pos)
    else if start_line <= line && line <= end_line then Some (0, width)
    else None

  let to_image
      (buffer : t)
      (top_line : int)
      ((w, h) : int * int)
      (show_cursor : bool) =
    let visual_h = h - 1 in
    let visual_w = w - 5 in
    let line_numbers = Orender.make_line_numbers visual_h in
    let bounds = compute_hl_bounds buffer in
    let editor_img =
      buffer_contents buffer
      |> Util.pad_to (visual_w, visual_h)
      |> Util.list_from_nth top_line
      |> List.mapi (fun i ->
             Orender.image_of_string
               (get_hl_opt buffer visual_w bounds i)
               (get_cursor_opt buffer show_cursor i))
      |> Orender.crop_to (visual_w, visual_h)
    in
    line_numbers <|> editor_img <-> modeline_to_image buffer visual_w

  let update_on_key (buffer : t) (key : Unescape.key) =
    match key with
    | `Enter, _ -> insert_newline buffer
    | `ASCII 'P', [ `Ctrl ] -> toggle_mark buffer
    (* | `ASCII 'F', [ `Ctrl ] -> forward_word buffer | `ASCII 'B', [
       `Ctrl ] -> backward_word buffer *)
    | `ASCII ch, _ -> insert_char buffer ch
    | `Backspace, _ | `Delete, _ -> delete buffer
    | `Arrow direxn, _ -> mv_cursor buffer direxn
    | _ -> buffer
end
