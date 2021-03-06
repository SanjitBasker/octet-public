(** Buffer types. *)

module type MUT_BUFFER = sig
  type t
  (** [t] is the type of a mutable buffer for the contents of a line. *)

  val make : string -> int -> t
  (** [make str len] creates a buffer that can support strings of size
      up to [len] before any resizing is needed, and is initialized to
      contain [str] with the cursor directly after [str]. *)

  val insert : t -> char -> unit
  (** [insert buf c] inserts [c] at the location of the cursor and
      shifts the cursor to be after [c]. *)

  val delete : t -> unit
  (** [delete buf] deletes the character at the location of the cursor. *)

  val to_string : t -> string
  (** [to_string buf] is a string with the contents of [buf]. *)

  val left : t -> unit
  (** [left buf] moves the cursor left one character. *)

  val right : t -> unit
  (** [right buf] moves the cursor right one character. *)

  val move_to : t -> int -> unit
  (** [move_to buf pos] moves the cursor so that there are [pos]
      characters to its left. *)

  val content_size : t -> int
  (** [content_size buf] is the number of characters [buf] is holding. *)
end

module type MUT_FILEBUFFER = sig
  type t
  (** [t] is the type of a buffer representing the contents of a file. *)

  val empty : unit -> t
  (** [empty ()] is an empty buffer. *)

  val from_file : string -> t
  (** [from_file s] is a buffer containing the contents of the path [s]. *)

  val write_to_file : t -> unit
  (** [write_to_file buffer] writes the contents of the buffer to the
      file it was initialized from. *)

  val to_image :
    t -> int ref -> int ref -> int * int -> bool -> Notty.I.t
  (** [to_image buffer top_line (h, w) show_cursor] is the image of
      [buffer] starting from [top_line], wrapped by width [w], cropped
      to height of [h], and containing the location of the cursor. It
      displays the cursor if [show_cursor = true]. *)

  val buffer_contents : t -> string list
  (** [buffer_contents buffer] is the contents of [buffer]. *)

  val ocaml_format : t -> t
  (** [ocaml_format buffer] is the buffer with the ocamlformat applied. *)

  val update_on_key : t -> Notty.Unescape.key -> t
  (** [update_on_key buffer key] is [buffer] updated according to the
      signal sent by [key]. *)

  val paste_from_clipboard : t -> t
  (** [paste_from_clipboard buffer] is [buffer] with the contents from
      the system clipboard pasted at the cursor position. *)

  val mv_search : t -> string -> t
  (** [mv_search buffer s] is [buffer] with cursor moved to the next
      appearance of [s] in a line below the current cursor location. *)
end
