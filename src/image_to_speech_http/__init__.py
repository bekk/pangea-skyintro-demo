import logging
import os
import datetime
import string
import random
from typing import Union
import traceback
import json

import azure.functions as func
import azure.storage.blob as blob
from azure.core.exceptions import ResourceExistsError
import azure.cognitiveservices. vision.computervision as cv
import azure.cognitiveservices.speech as speech
import msrest.authentication as azauth


class FunctionError(Exception):
    def __init__(self, message, status_code):
        super().__init__()
        self.message = message
        self.status_code = status_code

    def __str__(self):
        return f"{self.message} ({self.status_code})"


def get_storage_connection_string() -> str:
    return os.environ["AzureWebJobsStorage"]


def create_storage_account_container_if_not_exists(storage_account_client: blob.BlobServiceClient, container_name: str) -> None:
    try:
        storage_account_client.create_container(container_name)
    except ResourceExistsError:
        pass  # Container already exists, silently ignore


def generate_blob_read_sas_url(blob_client: blob.BlobClient, time_span: datetime.timedelta) -> str:
    sas = blob.generate_blob_sas(
        account_name=blob_client.account_name,
        container_name=blob_client.container_name,
        blob_name=blob_client.blob_name,
        account_key=blob_client.credential.account_key,
        permission=blob.BlobSasPermissions.from_string("r"),
        expiry=datetime.datetime.utcnow() + time_span
    )

    base_url = blob_client.url

    return f"{base_url}?{sas}"


def get_computer_vision_image_description(image_url: str) -> Union[str, None]:
    endpoint = os.environ["ComputerVisionEndpoint"]
    account_key = os.environ["ComputerVisionAccountKey"]
    cognitiveservices_client = cv.ComputerVisionClient(endpoint=endpoint, credentials=azauth.CognitiveServicesCredentials(account_key))

    description_results = cognitiveservices_client.describe_image(image_url)

    num_captions = len(description_results.captions)
    if num_captions == 0:
        raise FunctionError("No results from computer vision API", 500)

    best_caption = max(description_results.captions, key=lambda c: c.confidence)
    description = best_caption.text
    logging.info("Got image description: %s", description)

    return description


def get_speech_audio_for_text(text: str) -> Union[bytes, None]:
    key = os.environ["SpeechKey"]
    location = os.environ["SpeechLocation"]
    speech_config = speech.SpeechConfig(subscription=key, region=location)

    synthesizer = speech.SpeechSynthesizer(speech_config=speech_config, audio_config=None)
    result: speech.SpeechSynthesisResult = synthesizer.speak_text_async(text).get()
    reason: speech.ResultReason = result.reason

    if reason != speech.ResultReason.SynthesizingAudioCompleted:
        raise FunctionError(f"Failed to synthesize text.\nReason: {str(reason)}.\nText: {text}", 500)

    return result.audio_data


def upload_to_blob_and_generate_sas(storage_account_client: blob.BlobServiceClient, container_name: str, filename: str, content: bytes):
    create_storage_account_container_if_not_exists(storage_account_client, container_name)

    blob_client = storage_account_client.get_blob_client(container=container_name, blob=filename)
    blob_client.upload_blob(content, overwrite=True)
    logging.info("%s uploaded to container", filename)

    sas_url = generate_blob_read_sas_url(blob_client, datetime.timedelta(minutes=10))
    # logging.info(f"SAS URL: {sas_url}")

    return sas_url


def get_file_content_from_request(req: func.HttpRequest) -> bytes:
    files = list(req.files.values())
    if len(files) < 1:
        raise FunctionError("Expected attached file", 400)

    input_file = files[0]
    filename: str = input_file.filename

    if filename.rsplit('.', 1)[1] not in ('jpg', 'jpeg', 'png', 'gif', 'bmp'):  # Supported according to documentation
        raise FunctionError(f"Invalid filetype for file {filename}", 400)

    logging.info("Received file with filename: %s", filename)
    return input_file.stream.read()


def main(req: func.HttpRequest) -> func.HttpResponse:
    try:
        logging.info("Python HTTP trigger function processed a request.")

        content = get_file_content_from_request(req)
        randomized_filename = ''.join(random.choices(string.ascii_lowercase, k=30))

        # establish connection to storage account
        storage_connection_string = get_storage_connection_string()
        storage_account_client = blob.BlobServiceClient.from_connection_string(storage_connection_string)

        # get description of image
        image_sas_url = upload_to_blob_and_generate_sas(storage_account_client, 'images', randomized_filename, content)
        description = get_computer_vision_image_description(image_sas_url)

        # convert description to speech
        audio_data = get_speech_audio_for_text(description)
        audio_sas_url = upload_to_blob_and_generate_sas(storage_account_client, 'audio', randomized_filename+'.wav', audio_data)

        response = {"success": True, "url": audio_sas_url}
        return func.HttpResponse(json.dumps(response), status_code=200)

    except FunctionError as e:
        logging.error(e.message, exc_info=e)
        response = {"success": False, "message": e.message}
        return func.HttpResponse(json.dumps(response), status_code=e.status_code)
    except Exception as e:
        message = f"Unhandled exception: {e}"
        logging.error(message, exc_info=e)
        response = {"success": False, "message": message}
        return func.HttpResponse(json.dumps(response), status_code=500)
