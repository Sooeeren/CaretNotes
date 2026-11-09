# Features in detail

## Pen and ink

- **Pens:** pressure-sensitive pen, fineliner and pencil, each with its own width and color. Tap the active pen again for its options.
- **Highlighter** that always stays behind your writing, so it never covers ink.
- **Eraser:** whole strokes or partial, with an adjustable size.
- **S Pen side button:** hold it for the eraser or for selection (Settings).
- **Palm rejection:** while the pen is down or hovering, and for half a second after it lifts, touches are ignored. A palm that was already resting when the pen arrived is cancelled too.
- **Hold to straighten:** keep the pen still at the end of a line and it snaps straight. Rough rectangles, circles, triangles and arrows become clean shapes. Keep moving the pen before lifting to adjust the shape.
- **Ruler:** move and rotate it with two fingers. It snaps to 0°, 45° and 90°, shows the angle and centimeter marks, and lines drawn near its edge stick to it.

## Selection

Freehand lasso or a box. Move, resize, rotate, recolor, copy, paste, duplicate, delete, or save the selection as an image. Text typed on lines snaps back onto the lines when you move it.

## Typing

The text tool has two modes. Tap the active text tool to switch.

- **On lines:** click a line and type. The text spans the writing area, every line sits on a ruled line, and Enter goes to the next one, like writing in a notebook. On Cornell paper the cue column and the notes column each get their own text. If you change the line spacing later, the text moves to the new lines.
- **Text box:** click anywhere for a free box you can move and resize.

Both understand Markdown as you type: headings, **bold**, *italic*, lists, checkboxes, code, quotes and links. Text boxes also render tables, code blocks with syntax highlighting and LaTeX math (`$x^2$`). A small bar above the text inserts the formatting for you.

## Paper

The template picker (⋮ → **Paper template…**) shows a preview of every paper:

| Paper | Use |
| --- | --- |
| Blank | Sketches, slides |
| Lined, narrow lined, wide lined | Writing; with a notebook margin |
| Cornell | Cue column, notes and a summary area at the bottom |
| Grid 5 mm, grid 1 cm | Math, diagrams |
| Dots | Bullet journals, sketches |
| Music staff | Sheet music |

Choose white, cream, mint or dark paper and fine-tune the spacing. A template can be set for the whole note or for a single page.

## Layouts

- **Pages** in A4 or Letter, with a page overview to reorder, duplicate and delete pages.
- **One endless page** that grows as you write.
- **An infinite canvas** in every direction.

## Images and PDFs

- Insert images from a file, paste them (Ctrl+V) or drag them in. Move, resize, rotate, crop, or put them behind the ink.
- Import lecture slides as a PDF and write on them; add blank pages in between.

## Export

- **PDF** with vector ink, real (searchable) text, and imported PDF pages at their original quality.
- **PNG or JPG** of a page or a selection.

## Library

- Nested folders with colors and icons, sorting (or your own order by drag and drop), multi-select to move or delete.
- Favorites, Recent, search across titles and typed text.
- **Recently deleted** keeps everything for 30 days, including versions replaced by sync.

## Your notes

Notes are stored in `%APPDATA%\dev.caretnotes\caret_notes\library` (Settings → Device & storage shows the exact path). Each note is one `.cnote` file: a zip with `note.json`, the embedded images and PDFs, and a thumbnail. Files are saved atomically (written to a temporary file first), so a crash never leaves a half-written note. The editor saves 1.5 seconds after a change, and when you close the note or the app.

A note written by a newer CaretNotes version is listed as unreadable in an older one instead of being opened and overwritten.
