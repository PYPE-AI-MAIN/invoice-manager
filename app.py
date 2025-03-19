from flask import Flask, redirect, url_for, render_template, session, request, jsonify
import os
import re
import base64
import email
import json
import tempfile
from datetime import datetime, timedelta
from email.utils import parsedate_to_datetime
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload
from dotenv import load_dotenv
import traceback
import logging

# Setup logging
logging.basicConfig(
    filename='app.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

# Load environment variables
load_dotenv()

# Configure constants
DATA_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')
os.makedirs(DATA_DIR, exist_ok=True)

# Enable insecure transport for OAuth only in development environment
if os.environ.get('FLASK_ENV') == 'development':
    os.environ['OAUTHLIB_INSECURE_TRANSPORT'] = '1'
    print("WARNING: OAuth insecure transport enabled for development. Never use this in production!")

# Initialize Flask app
app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev_key')
app.template_folder = 'templates'
app.static_folder = 'static'

#----------------
# Data Storage
#----------------

def get_user_data_path(user_email):
    """Get path to user's data file"""
    safe_email = re.sub(r'[^\w\-_]', '_', user_email)
    return os.path.join(DATA_DIR, f"{safe_email}.json")

def save_user_data(user_email, user_data):
    """Save user data to file"""
    try:
        with open(get_user_data_path(user_email), 'w') as f:
            json.dump(user_data, f)
        logging.info(f"Saved data for user: {user_email}")
    except Exception as e:
        logging.error(f"Error saving user data: {str(e)}")
        raise

def get_user_data(user_email):
    """Get user data from file"""
    data_path = get_user_data_path(user_email)
    if os.path.exists(data_path):
        try:
            with open(data_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            logging.error(f"Error loading user data: {str(e)}")
    return None

def update_user_credentials(user_email, credentials):
    """Update user's Google credentials"""
    user_data = get_user_data(user_email) or {
        "email": user_email,
        "name": user_email.split('@')[0],
        "google_credentials": None,
        "created_at": datetime.utcnow().isoformat(),
        "invoices": []
    }
    
    user_data["google_credentials"] = credentials
    user_data["updated_at"] = datetime.utcnow().isoformat()
    
    save_user_data(user_email, user_data)

def add_invoice(user_email, invoice_data):
    """Add invoice data to user's records"""
    user_data = get_user_data(user_email)
    if not user_data:
        return False
        
    # Add a unique ID and created timestamp
    invoice_data["id"] = f"inv_{int(datetime.utcnow().timestamp())}_{len(user_data['invoices'])}"
    invoice_data["created_at"] = datetime.utcnow().isoformat()
    
    user_data["invoices"].append(invoice_data)
    save_user_data(user_email, user_data)
    return True

#----------------
# Google Authentication
#----------------

def create_oauth_flow(redirect_uri=None):
    """Create OAuth 2.0 flow object for authentication"""
    redirect_uri = redirect_uri or os.environ.get("GOOGLE_REDIRECT_URI")
    
    client_config = {
        "web": {
            "client_id": os.environ.get("GOOGLE_CLIENT_ID"),
            "client_secret": os.environ.get("GOOGLE_CLIENT_SECRET"),
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": [redirect_uri]
        }
    }
    
    scopes = os.environ.get("GOOGLE_SCOPES", "https://www.googleapis.com/auth/gmail.readonly https://www.googleapis.com/auth/drive").split()
    
    # Create flow with explicit redirect URI
    flow = Flow.from_client_config(
        client_config,
        scopes=scopes,
        redirect_uri=redirect_uri
    )
    
    return flow

def credentials_from_dict(credentials_dict):
    """Create Credentials object from dictionary"""
    if not credentials_dict:
        return None
        
    return Credentials(
        token=credentials_dict.get('token'),
        refresh_token=credentials_dict.get('refresh_token'),
        token_uri=credentials_dict.get('token_uri', "https://oauth2.googleapis.com/token"),
        client_id=os.environ.get("GOOGLE_CLIENT_ID"),
        client_secret=os.environ.get("GOOGLE_CLIENT_SECRET"),
        scopes=credentials_dict.get('scopes')
    )
    
def credentials_to_dict(credentials):
    """Convert Credentials object to dictionary for storage"""
    if not credentials:
        return None
        
    return {
        'token': credentials.token,
        'refresh_token': credentials.refresh_token,
        'token_uri': credentials.token_uri,
        'client_id': credentials.client_id,
        'client_secret': credentials.client_secret,
        'scopes': credentials.scopes
    }

#----------------
# Gmail Service
#----------------

def build_gmail_service(credentials):
    """Build Gmail API service"""
    credentials_obj = credentials_from_dict(credentials)
    if not credentials_obj:
        return None
    
    return build('gmail', 'v1', credentials=credentials_obj)

def list_invoice_emails(service, start_date=None, end_date=None):
    """List emails that potentially contain invoices"""
    if not start_date:
        start_date = datetime.utcnow() - timedelta(days=30)
    
    if not end_date:
        end_date = datetime.utcnow()
    
    # Format dates for Gmail query
    after_date = start_date.strftime('%Y/%m/%d')
    before_date = end_date.strftime('%Y/%m/%d')
    
    # Query for emails with attachments that might be invoices
    query = f"has:attachment after:{after_date} before:{before_date} " \
            f"(subject:invoice OR subject:receipt OR subject:bill OR subject:statement OR subject:payment)"
    
    try:
        results = service.users().messages().list(userId='me', q=query, maxResults=100).execute()
        messages = results.get('messages', [])
        return messages
    except Exception as e:
        logging.error(f"Error fetching invoice emails: {str(e)}")
        return []

def get_email_content(service, msg_id):
    """Get full content of an email message"""
    try:
        message = service.users().messages().get(userId='me', id=msg_id, format='full').execute()
        return message
    except Exception as e:
        logging.error(f"Error getting email content: {str(e)}")
        return None

def extract_email_data(message):
    """Extract relevant data from email message"""
    if not message or 'payload' not in message:
        return None
        
    headers = message['payload']['headers']
    
    # Extract subject and sender
    subject = ""
    sender = ""
    sender_email = ""
    for header in headers:
        if header['name'] == 'Subject':
            subject = header['value']
        if header['name'] == 'From':
            sender = header['value']
            # Extract just the email part
            email_match = re.search(r'<(.+?)>', sender)
            if email_match:
                sender_email = email_match.group(1)
            else:
                sender_email = sender
    
    # Extract date
    date_str = next((header['value'] for header in headers if header['name'] == 'Date'), None)
    try:
        date = email.utils.parsedate_to_datetime(date_str) if date_str else datetime.utcnow()
    except:
        date = datetime.utcnow()
        
    return {
        'message_id': message['id'],
        'subject': subject,
        'sender': sender,
        'sender_email': sender_email,
        'date': date,
        'has_attachments': 'parts' in message['payload']
    }

def get_attachment(service, message_id, attachment_id, attachment_filename):
    """Download an email attachment"""
    try:
        attachment = service.users().messages().attachments().get(
            userId='me', 
            messageId=message_id, 
            id=attachment_id
        ).execute()
        
        file_data = base64.urlsafe_b64decode(attachment['data'])
        
        # Create temporary file to store the attachment
        temp_dir = tempfile.gettempdir()
        file_path = os.path.join(temp_dir, attachment_filename)
        
        with open(file_path, 'wb') as f:
            f.write(file_data)
            
        return file_path
    except Exception as e:
        logging.error(f"Error downloading attachment: {str(e)}")
        return None

def list_attachments(message):
    """List all attachments in an email message"""
    if not message or 'payload' not in message:
        return []
        
    attachments = []
    
    def extract_attachments(message_part):
        if message_part.get('mimeType') == 'multipart/mixed' or message_part.get('mimeType') == 'multipart/related' or message_part.get('mimeType') == 'multipart/alternative':
            for part in message_part.get('parts', []):
                extract_attachments(part)
        elif message_part.get('mimeType') in ['application/pdf', 'image/jpeg', 'image/png', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'application/msword']:
            if 'body' in message_part and 'attachmentId' in message_part['body']:
                attachments.append({
                    'id': message_part['body']['attachmentId'],
                    'filename': message_part.get('filename', f"attachment_{message_part['body']['attachmentId']}"),
                    'mimeType': message_part['mimeType'],
                    'size': message_part['body'].get('size', 0)
                })
                
    if 'parts' in message['payload']:
        for part in message['payload']['parts']:
            extract_attachments(part)
            
    return attachments

#----------------
# Google Drive Service
#----------------

def build_drive_service(credentials):
    """Build Google Drive API service"""
    credentials_obj = credentials_from_dict(credentials)
    if not credentials_obj:
        return None
        
    return build('drive', 'v3', credentials=credentials_obj)

def upload_file(service, file_path, folder_id, file_name=None):
    """Upload a file to Google Drive"""
    if not file_name:
        file_name = os.path.basename(file_path)
        
    try:
        file_metadata = {
            'name': file_name,
            'parents': [folder_id] if folder_id else []
        }
        
        media = MediaFileUpload(file_path, resumable=True)
        file = service.files().create(
            body=file_metadata,
            media_body=media,
            fields='id,webViewLink'
        ).execute()
        
        return {
            'file_id': file.get('id'),
            'web_link': file.get('webViewLink')
        }
    except Exception as e:
        logging.error(f"Error uploading file to Google Drive: {str(e)}")
        return None

def upload_file_to_shared_drive(service, file_path, folder_id, drive_id, file_name=None):
    """Upload a file to a shared Google Drive folder"""
    if not file_name:
        file_name = os.path.basename(file_path)
        
    try:
        logging.info(f"Uploading file '{file_name}' to shared drive ID: {drive_id}, folder ID: {folder_id}")
        file_metadata = {
            'name': file_name,
            'parents': [folder_id] if folder_id else []
        }
        
        media = MediaFileUpload(file_path, resumable=True)
        file = service.files().create(
            body=file_metadata,
            media_body=media,
            fields='id,webViewLink',
            supportsAllDrives=True
        ).execute()
        
        result = {
            'file_id': file.get('id'),
            'web_link': file.get('webViewLink')
        }
        logging.info(f"Successfully uploaded file '{file_name}' to Google Drive with ID: {result['file_id']}")
        return result
    except Exception as e:
        logging.error(f"Error uploading file to Google Drive: {str(e)}")
        return None

def find_or_create_folder(service, folder_name, parent_folder_id=None):
    """Find a folder by name or create if it doesn't exist"""
    try:
        query = f"mimeType='application/vnd.google-apps.folder' and name='{folder_name}'"
        if parent_folder_id:
            query += f" and '{parent_folder_id}' in parents"
            
        results = service.files().list(q=query, fields="files(id, name)").execute()
        folders = results.get('files', [])
        
        if folders:
            return folders[0]['id']
        else:
            # Create the folder
            file_metadata = {
                'name': folder_name,
                'mimeType': 'application/vnd.google-apps.folder',
                'parents': [parent_folder_id] if parent_folder_id else []
            }
            
            folder = service.files().create(
                body=file_metadata,
                fields='id'
            ).execute()
            
            return folder.get('id')
    except Exception as e:
        logging.error(f"Error finding or creating folder: {str(e)}")
        return None

def find_or_create_folder_in_shared_drive(service, folder_name, drive_id, parent_folder_id=None):
    """Find a folder by name in a shared drive or create if it doesn't exist"""
    try:
        logging.info(f"Finding folder '{folder_name}' in shared drive ID: {drive_id}, parent: {parent_folder_id}")
        query = f"name='{folder_name}' and mimeType='application/vnd.google-apps.folder' and trashed=false"
        
        # Add parent folder constraint if provided
        if parent_folder_id:
            query += f" and '{parent_folder_id}' in parents"
            
        # For the shared drive root, we need different parameters
        if drive_id:
            parameters = {
                'q': query,
                'fields': 'files(id, name)',
                'corpora': 'drive',
                'driveId': drive_id,
                'includeItemsFromAllDrives': True,
                'supportsAllDrives': True
            }
        else:
            # For regular folders
            parameters = {
                'q': query,
                'fields': 'files(id, name)',
                'supportsAllDrives': True
            }
        
        results = service.files().list(**parameters).execute()
        folders = results.get('files', [])
        
        if folders:
            logging.info(f"Found existing folder '{folder_name}' with ID: {folders[0]['id']}")
            return folders[0]['id']
        else:
            logging.info(f"Creating new folder: {folder_name}")
            return create_folder_in_shared_drive(service, folder_name, drive_id, parent_folder_id)
    except Exception as e:
        logging.error(f"Error finding or creating folder in shared drive: {str(e)}")
        return None

def create_folder_in_shared_drive(service, folder_name, drive_id, parent_folder_id=None):
    """Create a folder in a shared drive"""
    try:
        logging.info(f"Creating folder '{folder_name}' in shared drive ID: {drive_id}, parent: {parent_folder_id}")
        file_metadata = {
            'name': folder_name,
            'mimeType': 'application/vnd.google-apps.folder'
        }
        
        # Add the drive ID as a parent if no parent folder is specified
        if parent_folder_id:
            file_metadata['parents'] = [parent_folder_id]
        elif drive_id:
            file_metadata['parents'] = [drive_id]
        
        folder = service.files().create(
            body=file_metadata,
            supportsAllDrives=True,
            fields='id'
        ).execute()
        
        folder_id = folder.get('id')
        logging.info(f"Created folder '{folder_name}' with ID: {folder_id}")
        return folder_id
    except Exception as e:
        logging.error(f"Error creating folder in shared drive: {str(e)}")
        return None

def clean_drive_id(drive_id):
    """Extract just the ID part from a Google Drive URL if needed"""
    if not drive_id:
        return None
        
    # If it's a URL, extract just the ID part
    if 'drive.google.com' in drive_id:
        match = re.search(r'folders/([^/?&]+)', drive_id)
        if match:
            return match.group(1)
    
    return drive_id

def create_drive_folder_structure(service, year, month, user_name):
    """Create folder structure in a shared drive: shared drive --> year/month --> user name"""
    
    # Get the shared drive ID from environment and clean it
    raw_drive_id = os.environ.get('GOOGLE_SHARED_DRIVE_ID')
    shared_drive_id = clean_drive_id(raw_drive_id)
    
    logging.info(f"Using shared drive ID: {shared_drive_id}")
    
    # Format month name
    month_date = datetime(year, month, 1)
    month_name = month_date.strftime("%B")
    
    try:
        # Step 1: Find or create year folder in the shared drive
        year_folder_name = str(year)
        year_folder_id = find_or_create_folder_in_shared_drive(
            service, 
            year_folder_name,
            shared_drive_id
        )
        
        if not year_folder_id:
            logging.error("Failed to create year folder in shared drive")
            return None
        
        # Step 2: Find or create month folder
        month_folder_id = find_or_create_folder_in_shared_drive(
            service, 
            month_name, 
            shared_drive_id,
            year_folder_id
        )
        
        if not month_folder_id:
            logging.error("Failed to create month folder in shared drive")
            return None
        
        # Step 3: Find or create user folder
        user_folder_id = find_or_create_folder_in_shared_drive(
            service, 
            user_name, 
            shared_drive_id,
            month_folder_id
        )
        
        if not user_folder_id:
            logging.error("Failed to create user folder in shared drive")
            return None
        
        # Files will be placed directly into the user folder
        return {
            'folder_id': user_folder_id,
            'drive_id': shared_drive_id
        }
            
    except Exception as e:
        logging.error(f"Error creating folder structure: {str(e)}")
        return None

#----------------
# Invoice Processing
#----------------

def process_and_upload_invoices_by_month(user_email, year, month):
    """Process invoices for a specific month and year and save to shared drive"""
    logging.info(f"Processing invoices for user: {user_email} for {month}/{year}")
    
    # Get user data
    user_data = get_user_data(user_email)
    if not user_data or 'google_credentials' not in user_data:
        return {
            'success': False, 
            'message': 'User credentials not found.'
        }
    
    # Build Gmail service
    gmail_service = build_gmail_service(user_data['google_credentials'])
    if not gmail_service:
        return {
            'success': False, 
            'message': 'Failed to build Gmail service.'
        }
    
    # Build Drive service
    drive_service = build_drive_service(user_data['google_credentials'])
    if not drive_service:
        return {
            'success': False, 
            'message': 'Failed to build Drive service.'
        }
    
    # Create start and end dates for the month
    start_date = datetime(year, month, 1)
    
    # Determine the last day of the month
    if month == 12:
        next_month = datetime(year + 1, 1, 1)
    else:
        next_month = datetime(year, month + 1, 1)
    end_date = next_month - timedelta(days=1)
    
    # Query Gmail for emails with attachments for the specified month
    query = f"has:attachment after:{start_date.strftime('%Y/%m/%d')} before:{end_date.strftime('%Y/%m/%d')} " \
            f"(subject:invoice OR subject:receipt OR subject:bill OR subject:statement OR subject:payment)"
    
    try:
        results = gmail_service.users().messages().list(userId='me', q=query, maxResults=100).execute()
        messages = results.get('messages', [])
        
        if not messages:
            return {
                'success': True, 
                'message': f'No invoice emails found for {start_date.strftime("%B %Y")}.', 
                'count': 0
            }
        
        logging.info(f"Found {len(messages)} potential invoice emails for {start_date.strftime('%B %Y')}")
        
        # Create folder structure in Google Drive
        folder_info = create_drive_folder_structure(
            drive_service,
            year,
            month,
            user_data['name']
        )
        
        if not folder_info:
            return {
                'success': False,
                'message': 'Failed to create folder structure in Google Drive.'
            }
        
        invoices_folder_id = folder_info['folder_id']
        drive_id = folder_info['drive_id']
        
        # Process each message
        processed_count = 0
        processed_files = []
        
        for msg in messages:
            try:
                # Get message content
                message = get_email_content(gmail_service, msg['id'])
                if not message:
                    continue
                    
                # Extract email data
                email_data = extract_email_data(message)
                if not email_data or not email_data.get('has_attachments'):
                    continue
                    
                # Find attachments
                attachments = list_attachments(message)
                if not attachments:
                    continue
                
                # Find invoices already processed to avoid duplicates
                existing_invoices = [inv for inv in user_data.get('invoices', []) 
                                    if inv.get('message_id') == email_data['message_id']]
                already_processed = len(existing_invoices) > 0
                
                # Process each attachment
                for attachment in attachments:
                    if attachment['mimeType'] in ['application/pdf', 'image/jpeg', 'image/png', 
                                                 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 
                                                 'application/msword']:
                        # Download attachment
                        file_path = get_attachment(
                            gmail_service, 
                            email_data['message_id'], 
                            attachment['id'],
                            attachment['filename']
                        )
                        
                        if file_path:
                            # Generate filename with date info
                            received_date = email_data['date'].strftime('%Y%m%d')
                            new_filename = f"{received_date}_{attachment['filename']}"
                            
                            # Upload to Google Drive in the appropriate folder
                            result = upload_file_to_shared_drive(
                                drive_service, 
                                file_path, 
                                invoices_folder_id,
                                drive_id,
                                new_filename
                            )
                            
                            if result:
                                # Save to local JSON store if not already processed
                                if not already_processed:
                                    invoice_data = {
                                        'filename': new_filename,
                                        'sender': email_data['sender'],
                                        'subject': email_data['subject'],
                                        'received_date': email_data['date'].isoformat(),
                                        'gdrive_link': result['web_link'],
                                        'message_id': email_data['message_id']
                                    }
                                    add_invoice(user_data['email'], invoice_data)
                                
                                processed_count += 1
                                processed_files.append({
                                    'name': new_filename,
                                    'link': result['web_link'],
                                })
                                
                                logging.info(f"Successfully processed invoice: {new_filename}")
                                
                            # Clean up temp file
                            if os.path.exists(file_path):
                                os.remove(file_path)
            except Exception as e:
                logging.error(f"Error processing message: {str(e)}")
                continue
        
        # Return success result with folder information
        folder_link = None
        try:
            # Get the folder link with support for shared drives
            folder = drive_service.files().get(
                fileId=invoices_folder_id, 
                fields='webViewLink',
                supportsAllDrives=True
            ).execute()
            folder_link = folder.get('webViewLink')
        except Exception as e:
            logging.error(f"Error getting folder link: {str(e)}")
        
        return {
            'success': True, 
            'message': f'Successfully processed {processed_count} invoices for {start_date.strftime("%B %Y")}.', 
            'count': processed_count,
            'files': processed_files,
            'folder_link': folder_link
        }
    except Exception as e:
        logging.error(f"Error processing invoices: {str(e)}")
        return {
            'success': False, 
            'message': f'Error processing invoices: {str(e)}'
        }

#----------------
# Routes
#----------------

@app.route('/')
def index():
    """Root route redirects to dashboard or login"""
    if 'user_email' not in session:
        return redirect(url_for('login'))
    return redirect(url_for('dashboard'))

@app.route('/login')
def login():
    """Render login page"""
    return render_template('login.html')

@app.route('/authorize')
def authorize():
    """Start OAuth flow for Google authentication"""
    # Create OAuth flow with explicit redirect URI
    redirect_uri = os.environ.get("GOOGLE_REDIRECT_URI")
    flow = create_oauth_flow(redirect_uri)
    
    # Generate authorization URL
    authorization_url, state = flow.authorization_url(
        access_type='offline',
        include_granted_scopes='true',
        prompt='consent'  # Force to display consent screen to get refresh_token
    )
    
    # Store state in session for verification
    session['state'] = state
    
    # Redirect the user to the authorization URL
    return redirect(authorization_url)

@app.route('/oauth2callback')
def oauth2callback():
    """Handle OAuth callback from Google"""
    # Check state to prevent CSRF
    state = session.get('state')
    if not state or state != request.args.get('state'):
        return jsonify({'error': 'Invalid state parameter'}), 400
    
    # Create OAuth flow with stored state and explicit redirect URI
    redirect_uri = os.environ.get("GOOGLE_REDIRECT_URI")
    flow = create_oauth_flow(redirect_uri)
    
    # Get the authorization code from the request
    code = request.args.get('code')
    if not code:
        return jsonify({'error': 'No authorization code provided'}), 400
        
    # Exchange authorization code for credentials
    try:
        flow.fetch_token(
            authorization_response=request.url
        )
        
        # Get credentials
        credentials = flow.credentials
        credentials_dict = credentials_to_dict(credentials)
        
        # Get user info from Gmail
        gmail_service = build_gmail_service(credentials_dict)
        user_info = gmail_service.users().getProfile(userId='me').execute()
        
        # Store or update user credentials
        update_user_credentials(user_info['emailAddress'], credentials_dict)
        
        # Store user info in session
        session['user_email'] = user_info['emailAddress']
        
        return redirect(url_for('dashboard'))
    except Exception as e:
        logging.error(f"OAuth callback error: {str(e)}")
        return jsonify({'error': f'Authentication error: {str(e)}'}), 400

@app.route('/logout')
def logout():
    """Log out user"""
    # Clear session
    session.clear()
    return redirect(url_for('login'))

@app.route('/dashboard')
def dashboard():
    """Render the dashboard page"""
    if 'user_email' not in session:
        return redirect(url_for('login'))
        
    # Get user data
    user_data = get_user_data(session['user_email'])
    if not user_data:
        return redirect(url_for('logout'))
    
    # Get current year and month
    current_year = datetime.now().year
    current_month = datetime.now().month
    
    return render_template('dashboard.html', 
                         user=user_data,
                         current_year=current_year,
                         current_month=current_month)

@app.route('/fetch-invoices', methods=['GET', 'POST'])
def fetch_invoices():
    """Fetch and upload invoices"""
    if 'user_email' not in session:
        return redirect(url_for('login'))
    
    # For GET requests, show the fetch form
    if request.method == 'GET':
        current_year = datetime.now().year
        return render_template('fetch_invoices.html', current_year=current_year)
    
    # For POST requests, process the fetch operation
    if request.method == 'POST':
        data = request.get_json()
        
        year = int(data.get('year', datetime.now().year))
        month = int(data.get('month', datetime.now().month))
        
        # Process the invoices for the specified month
        result = process_and_upload_invoices_by_month(
            session['user_email'], 
            year, 
            month
        )
        
        return jsonify(result)

# Main entry point
if __name__ == "__main__":
    import os
    debug_mode = os.environ.get('FLASK_DEBUG', '0') == '1'
    port = int(os.environ.get('PORT', 5001))
    app.run(debug=debug_mode, host='0.0.0.0', port=port)