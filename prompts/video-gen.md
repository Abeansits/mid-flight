Generate exactly one video from the description below.

If a reference image is listed, that file is the opening frame. Further reference images guide the clip. Call image_to_video with that opening frame. Do not pass aspect_ratio to image_to_video. The opening frame already has its shape.

If no reference image is listed, first call image_gen to create one still of the scene, then call image_to_video with that still as the opening frame. If the request names an aspect ratio, set it on that image_gen call, not on image_to_video.

Print only the absolute path of the saved video file.
