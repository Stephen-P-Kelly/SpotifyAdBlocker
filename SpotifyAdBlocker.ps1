# Replace these with your actual Spotify application credentials
$clientId = "be59d3da1e7a4dad954c8d3ed1c4c474"
$clientSecret = "494314ce747246cb860eca85d3067745"

# Spotify Web API endpoints
$authBaseUrl = "https://accounts.spotify.com"
$apiBaseUrl = "https://api.spotify.com/v1"

# Redirect URI used in your Spotify application settings
$redirectUri = "http://localhost:3000" # Update if needed

# Scopes needed for the API call
$scope = "user-read-currently-playing"

# Construct the authorization URL
$authUrl = "--new-window $authBaseUrl/authorize?client_id=$clientId&response_type=code&redirect_uri=$redirectUri&scope=$scope"

# Start a local web server to receive the authorization code automatically
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($redirectUri + "/")
$listener.Start()

# Open the authorization URL in the default web browser
$BrowserPath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
Start-Process -FilePath $BrowserPath -ArgumentList $authUrl

Start-Sleep -Seconds 1

# Get all Microsoft Edge processes
$edgeProcesses = Get-Process -Name "msedge" | Sort-Object StartTime

# Select the process with the least StartTime (i.e., the most recently started)
$specificEdgeProcess = $edgeProcesses | Select-Object -First 1

try {
    # Wait for the authorization code to be received from the local web server
    $context = $listener.GetContext()
    $code = $context.Request.QueryString["code"]

    # Close the local web server
    $listener.Stop()
    $listener.Close()

    # Stop the specific Microsoft Edge process by its PID
    Start-Sleep -Seconds 1
    $specificEdgeProcess.CloseMainWindow()

    # Exchange the authorization code for an access token
    $tokenUrl = "$authBaseUrl/api/token"
    $grantType = "authorization_code"
    $headers = @{ Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${clientId}:${clientSecret}")) }
    $body = @{
        grant_type    = $grantType
        code          = $code
        redirect_uri  = $redirectUri
    }

    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Headers $headers -Body $body
    $accessToken = $response.access_token

    # Create headers with the access token for API requests
    $headers = @{ Authorization = "Bearer $accessToken" }

    # Function to get the currently playing track
    function GetCurrentlyPlaying {
        $currentlyPlayingUrl = "$apiBaseUrl/me/player/currently-playing"
        $currentTrack = Invoke-RestMethod -Uri $currentlyPlayingUrl -Headers $headers

        return $currentTrack
    }

    # # Function to start or resume playback
    # function StartOrResumePlayback {
    #     Write-Host "called start function"
    #     $playbackUrl = "$apiBaseUrl/me/player/play"
    #     $body = @{
    #         context_uri  = $currentTrack.item.uri
    #         offset       = @{ position = 5 }
    #         position_ms  = 0
    #     } | ConvertTo-Json

    #     Invoke-RestMethod -Uri $playbackUrl -Method Put -Headers $headers -Body $body

    #     Write-Host "Playback started or resumed."
    # }



    # # If an ad or podcast is initially up, wait for a song to play
    # $currentTrack = GetCurrentlyPlaying
    # while ("$($currentTrack.item)".Length -eq 0) {
    #     Start-Sleep -Seconds 1
    #     $currentTrack = GetCurrentlyPlaying
    # }

    # Main loop
    $currentTrack = $null
    while ($true) {
        $currentTrackNameOld = $currentTrack.item.name
        $currentTrack = GetCurrentlyPlaying
        $currentTrackNameNew = $currentTrack.item.name

        if ($currentTrackNameOld -ne $currentTrackNameNew) {
            Write-Host "Now playing: $currentTrackNameNew"
        }

        if ("$($currentTrack.item)".Length -eq 0) {
            Write-Host "--- Podcast / Ad ---"

            # Get the current user's username
            $userName = $env:UserName

            # Get the Spotify process and kill it
            $spotifyProcess = Get-Process -Name "Spotify" -ErrorAction SilentlyContinue
            if ($spotifyProcess) {
                $spotifyProcess | Stop-Process -Force
            }

            # Sleep for a few seconds to allow the process to terminate completely
            Start-Sleep -Seconds 1

            # Rerun Spotify
            $spotifyPath = "C:\Users\$userName\AppData\Roaming\Spotify\Spotify.exe"
            Start-Process $spotifyPath

            while ("$($currentTrack.item)".Length -eq 0) {
                Start-Sleep -Seconds 1
                $currentTrack = GetCurrentlyPlaying
                # try {
                #     StartOrResumePlayback
                # } catch {
                #         if ($_.Exception.Response -ne $null) {
                #             $errorResponse = $_.Exception.Response.GetResponseStream()
                #             $reader = New-Object System.IO.StreamReader($errorResponse)
                #             $errorMessage = $reader.ReadToEnd() | ConvertFrom-Json
                #             Write-Host "Error: $($errorMessage.error.message)"
                #         } else {
                #             Write-Host "An unexpected error occurred. Please check your script and try again."
                #         }
                # }
            }

            # Set to null so that current track playing message prints
            $currentTrack = $null
        }

        # Buffer for Spotify API limit
        Start-Sleep -Seconds 1
    }
} catch {
    if ($null -ne $_.Exception.Response) {
        $errorResponse = $_.Exception.Response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($errorResponse)
        $errorMessage = $reader.ReadToEnd() | ConvertFrom-Json
        Write-Host "Error: $($errorMessage.error.message)"
    } else {
        Write-Host "An unexpected error occurred. Please check your script and try again."
    }
}
