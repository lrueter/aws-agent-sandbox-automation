# A Python image with your dependencies baked in. Sandboxes spawned from this
# image have the libraries pre-installed, so they work with ForgeVM's default
# "no network" isolation (no runtime pip install needed).
FROM python:3.12-slim

# Install dependencies from requirements.txt. Edit that file to add your libs.
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# (Optional) bake your application code into the image too, instead of uploading
# it at runtime:
# COPY app/ /app/
