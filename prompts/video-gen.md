Generate exactly one video from the description below.

On image_to_video, request 720p. If that tool lists resolution_name, set resolution_name to 720p. Do not pass a resolution the tool does not list. Do not invent another parameter name. A missing field or a lower tier can still save a smaller video. Do not describe the file as HD.

If a reference image is listed, the first file is the opening frame and its shape is the video shape. A 9:16 opening frame fits a portrait target. A 16:9 target needs a 16:9 opening frame. Later reference images guide the clip. They do not replace the opening frame. Call image_to_video with that opening frame. Do not pass aspect_ratio to image_to_video.

If no reference image is listed, first call image_gen to create one still of the scene, then call image_to_video with that still as the opening frame. If the request names an aspect ratio, set it on that image_gen call, not on image_to_video. That still's shape is the video shape.

Print only the absolute path of the saved video file.
