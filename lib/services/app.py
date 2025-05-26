import requests
from datetime import datetime

def fetch_stock_price(symbol):
    url = f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol.upper()}"

    try:
        response = requests.get(url, timeout=5)

        if response.status_code != 200:
            print(f"Error: HTTP {response.status_code} received from Yahoo Finance.")
            return

        try:
            data = response.json()
        except ValueError:
            print("Error: Failed to parse JSON. Raw response:")
            print(response.text)  # Debug print
            return

        if "chart" not in data or data["chart"].get("error"):
            print("Error: Yahoo Finance returned a chart error.")
            return

        result = data["chart"]["result"][0]
        timestamp = result["timestamp"][-1]
        close_price = result["indicators"]["quote"][0]["close"][-1]
        readable_time = datetime.fromtimestamp(timestamp).strftime('%Y-%m-%d %H:%M:%S')

        print(f"\nSymbol: {symbol.upper()}")
        print(f"Price:  ${close_price:.2f}")
        print(f"Time:   {readable_time}")

    except requests.exceptions.Timeout:
        print("Error: Request timed out.")
    except Exception as e:
        print("Unexpected error:", str(e))

if __name__ == "__main__":
    try:
        symbol = input("Enter stock symbol (default: AAPL): ").strip()
        if not symbol:
            symbol = "AAPL"
        fetch_stock_price(symbol)
    except EOFError:
        print("\nNo input received. Using default: AAPL")
        fetch_stock_price("AAPL")
