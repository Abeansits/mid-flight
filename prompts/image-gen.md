Generate exactly one image from the description below.

Use the image generation tool in this session. On Codex, invoke $imagegen. On Grok, call image_gen.

If the request names an aspect ratio and no reference image, use it. On Grok, pass aspect_ratio. On Codex, pass the Codex size written in the request.

If reference images are listed, use them. On Grok, call image_edit with those files. One reference keeps that file's aspect ratio. On Codex, use the attached reference images and the requested size.

Print only the absolute path of the saved image file.
