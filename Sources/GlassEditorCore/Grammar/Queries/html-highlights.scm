;; HTML — upstream's queries/highlights.scm at the pinned commit, with the two
;; additions this editor wants: the raw contents of <script> and <style> read as
;; embedded code rather than as ordinary text, and the doctype reads as a keyword
;; rather than a constant, which is what every other markup grammar here calls it.

(tag_name) @tag

(erroneous_end_tag_name) @tag.error

(doctype) @keyword

(attribute_name) @attribute

(attribute_value) @string

(quoted_attribute_value) @string

(comment) @comment

(entity) @constant

;; The text inside <script> and <style>. Not parsed as JavaScript or CSS — that is
;; an injection, and this build has no injection pass — but shown as code rather
;; than as prose, which is the honest half of the answer.
(script_element (raw_text) @embedded)

(style_element (raw_text) @embedded)

"=" @operator

[
  "<"
  ">"
  "</"
  "/>"
  "<!"
] @punctuation.bracket
