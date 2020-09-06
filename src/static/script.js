const url = 'https://pangea-skyintro-demo-funcapp.azurewebsites.net/api/image_to_speech_http'
const form = document.querySelector('form')
const p = document.querySelector('p')
const audio = document.querySelector('audio')

form.addEventListener('submit', (e) => {
  e.preventDefault()

  const files = document.querySelector('[type=file]').files
  const formData = new FormData()

  if (files.length > 0) {
    const file = files[0];
    formData.append('file', file)

    form.style.display = "none"
    p.style.display = ""
    audio.style.display = "none"

    fetch(url, {
      method: 'POST',
      body: formData,
    }).then((response) => {
      return response.json()
    }).then((json) => {
      console.log(json)
      audio.src = json["url"]
      p.style.display = "none"
      form.style.display = ""
      audio.style.display = ""
    })
  }
})
