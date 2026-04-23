# Azure Functions with SQL Triggers and Bindings (Python)

An Azure Functions QuickStart project that demonstrates how to use both SQL Triggers and SQL Output Bindings with the Azure Developer CLI (azd) for rapid, event-driven integration with Azure SQL Database using Python v2 programming model.

## Architecture

![Azure Functions SQL Output Binding Architecture](./diagrams/architecture.png)

This architecture shows how Azure Functions can both write to and react to changes in an Azure SQL Database using output bindings and triggers. The key components include:

- **Client Applications**: Send HTTP requests to the Azure Function
- **Azure Function with SQL Output Binding**: Receives HTTP requests and writes data to SQL Database
- **Azure Function with SQL Trigger**: Reacts to changes in SQL Database tables
- **Azure SQL Database**: Stores ToDo items
- **Azure Monitor**: Provides logging and metrics for the function execution

This serverless architecture enables scalable, event-driven data ingestion and processing with minimal code.

## Top Use Cases

### SQL Output Binding
1. **Data Ingestion API**: Quickly create APIs that write data to SQL Database without custom data access code.
2. **Serverless CRUD Operations**: Build serverless endpoints for line-of-business apps that interact with SQL data.

### SQL Trigger
1. **Change Data Capture & Auditing**: Automatically react to inserts, updates, or deletes in your SQL tables for auditing, notifications, or downstream processing.
2. **Event-Driven Workflows**: Trigger business logic or integration with other services when data changes in SQL, such as updating caches, sending alerts, or synchronizing systems.

## Features

* SQL Output Binding
* SQL Trigger
* Python v2 programming model
* Azure Functions Flex Consumption plan
* Azure Developer CLI (azd) integration for easy deployment
* Infrastructure as Code using Bicep templates
* Python 3.12 runtime

## Getting Started

### Prerequisites

- [Python 3.12](https://www.python.org/downloads/) or later
- [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local#install-the-azure-functions-core-tools)
- [Azure Developer CLI (azd)](https://docs.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azurite](https://github.com/Azure/Azurite) (for local Azure Storage emulation; can be run with `npx azurite`)
- An Azure subscription

### Quickstart

1. Clone this repository
   ```bash
   git clone https://github.com/Azure-Samples/functions-quickstart-python-azd-sql.git
   cd functions-quickstart-python-azd-sql
   ```

1. Provision Azure resources using azd
   ```bash
   azd provision
   ```
   This will create all necessary Azure resources including:
   - Azure SQL Database (default name: ToDo)
   - Azure Function App
   - App Service Plan
   - Other supporting resources
   - local.settings.json for local development with Azure Functions Core Tools, which should look like this:
   ```json
   {
     "IsEncrypted": false,
     "Values": {
       "AzureWebJobsStorage": "UseDevelopmentStorage=true",
       "FUNCTIONS_WORKER_RUNTIME": "python",
       "WEBSITE_SITE_NAME": "ToDo-local",
       "AZURE_SQL_CONNECTION_STRING_KEY": "Server=tcp:<server>.database.windows.net,1433;Database=ToDo;Authentication=Active Directory Default; TrustServerCertificate=True; Encrypt=True;"
     }
   }
   ```

   The `azd` command automatically sets up the required connection strings and application settings.

1. Set up Python virtual environment and install dependencies
   ```bash
   python -m venv .venv
   source .venv/bin/activate  # On Windows: .venv\Scripts\activate
   pip install -r requirements.txt
   ```

1. Start Azurite (local storage emulator)
   ```bash
   npx azurite --location ~/azurite-data
   ```

1. Start the function locally
   ```bash
   func start
   ```
   Or use VS Code to run the project with the built-in Azure Functions extension by pressing F5.

1. Test the function locally by sending a POST request to the HTTP endpoint:
   ```json
   {
     "id": "b1a7c1e2-1234-4f56-9abc-1234567890ab",
     "order": 1,
     "title": "Example: Walk the dog",
     "url": "https://example.com/todo/1",
     "completed": false
   }
   ```
   You can use tools like curl, Postman, or httpie:
   ```bash
   curl -X POST http://localhost:7071/api/httptriggersqloutput \
     -H "Content-Type: application/json" \
     -d '{"id":"b1a7c1e2-1234-4f56-9abc-1234567890ab","order":1,"title":"Example: Walk the dog","url":"https://example.com/todo/1","completed":false}'
   ```
   The function will write the item to the SQL database and return the created object.

1. Deploy to Azure
   ```bash
   azd up
   ```
   This will build your function app and deploy it to Azure. The deployment process:
   - Checks for any bicep changes using `azd provision`
   - Builds the Python project using `azd package`
   - Publishes the function app using `azd deploy`
   - Updates application settings in Azure

1. Test the deployed function by sending a POST request to the Azure Function endpoint (see Azure Portal for the URL).

## Understanding the Functions

### SQL Output Binding Function (`function_app.py` - `http_trigger_sql_output`)

This function receives HTTP POST requests and writes the payload to the SQL database using the SQL output binding. The key environment variable is:

- `AZURE_SQL_CONNECTION_STRING_KEY`: The identity-based connection string for the Azure SQL Database loaded from app settings or env vars

The function uses `command_text` instead of `table_name` to specify the SQL target table, which is a key feature of the SQL output binding in Azure Functions.

**Source code:**
```python
@app.function_name("httptrigger-sql-output")
@app.route(route="httptriggersqloutput", methods=["POST"])
@app.sql_output(arg_name="todo",
                command_text="[dbo].[ToDo]", 
                connection_string_setting="AZURE_SQL_CONNECTION_STRING_KEY")
def http_trigger_sql_output(req: func.HttpRequest, todo: func.Out[func.SqlRow]) -> func.HttpResponse:
    """HTTP trigger with SQL output binding to insert ToDo items."""
    # Parse the request body
    req_body = req.get_json()
    
    # Create SqlRow directly from the request body
    row = func.SqlRow.from_dict(req_body)
    todo.set(row)
    
    # Return success response
    return func.HttpResponse(
        json.dumps(req_body),
        status_code=201,
        mimetype="application/json"
    )
```
- Accepts a JSON body matching the database schema
- Writes the item to the `[dbo].[ToDo]` table in SQL using the `func.SqlRow.from_dict()` method
- Returns the created object as the HTTP response with a 201 Created status code

### SQL Trigger Function (`function_app.py` - `sql_trigger_todo`)

This function responds to changes in the SQL database. It enables event-driven processing whenever rows in the `[dbo].[ToDo]` table are inserted, updated, or deleted.

**Source code:**
```python
@app.sql_trigger(arg_name="changes", 
                 table_name="[dbo].[ToDo]",
                 connection_string_setting="AZURE_SQL_CONNECTION_STRING_KEY")
def sql_trigger_todo(changes: str) -> None:
    """SQL trigger function that responds to changes in the ToDo table."""
    logging.info("SQL trigger function processed changes")
    
    # Parse the changes string as JSON
    try:
        changes_list = json.loads(changes)
        
        for change in changes_list:
            # Get the operation type and item data
            operation = change.get('Operation', 'Unknown')
            item_data = change.get('Item', {})
            
            # Convert to ToDoItem for consistent handling
            todo_item = ToDoItem.from_dict(item_data)
            
            logging.info(f"Change operation: {operation}")
            logging.info(f"Id: {todo_item.id}, Title: {todo_item.title}, "
                        f"Url: {todo_item.url}, Completed: {todo_item.completed}")
    except json.JSONDecodeError:
        logging.error(f"Failed to parse changes as JSON: {changes}")
    except Exception as e:
        logging.error(f"Error processing changes: {str(e)}")
        logging.error(f"Changes content: {changes}")
```
- Monitors the `[dbo].[ToDo]` table for changes.
- Logs the operation type and details of each changed item.

### ToDoItem Model (`todo_item.py`)

```python
@dataclass
class ToDoItem:
    """ToDo item model for Azure SQL Database."""
    id: str
    title: str
    url: str
    order: Optional[int] = None
    completed: Optional[bool] = None
    
    def __init__(self, id: str = None, title: str = "", url: str = "", 
                 order: Optional[int] = None, completed: Optional[bool] = None):
        self.id = id if id is not None else str(uuid.uuid4())
        self.title = title
        self.url = url
        self.order = order
        self.completed = completed
```

- The model uses Python dataclass for clean data structure.
- All properties map directly by name and type to SQL columns.
- Includes helper methods for JSON conversion.

## Monitoring and Logs

You can monitor your function in the Azure Portal:
1. Navigate to your function app in the Azure Portal
2. Select "Functions" from the left menu
3. Click on your function (httptrigger-sql-output or sql_trigger_todo)
4. Select "Monitor" to view execution logs

Use the "Live Metrics" feature to see real-time information when testing.

## SQL Trigger Testing

1. Make a change to the `[dbo].[ToDo]` table in your Azure SQL Database (insert, update, or delete a row).
2. The `ToDoTrigger` function will automatically execute and log the change.
3. You can view the logs locally in your terminal or in the Azure Portal under your Function App's "Monitor" tab.

**Example Log Output:**
```
SQL trigger function processed changes
Change operation: Insert
Id: b1a7c1e2-1234-4f56-9abc-1234567890ab, Title: Example: Walk the dog, Url: https://example.com/todo/1, Completed: False
```

This enables you to build reactive, event-driven workflows based on changes in your SQL data.

## Troubleshooting

See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common deployment issues, including how to find a working Azure region when you encounter `ProvisioningDisabled` errors.

## Resources

- [Azure Functions SQL Bindings & Triggers Documentation (Microsoft Learn)](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-azure-sql?tabs=isolated-process%2Cextensionv4&pivots=programming-language-csharp)
- [Azure Functions Documentation](https://docs.microsoft.com/azure/azure-functions/)
- [Azure SQL Database Documentation](https://docs.microsoft.com/azure/azure-sql/)
- [Azure Developer CLI Documentation](https://docs.microsoft.com/azure/developer/azure-developer-cli/)
