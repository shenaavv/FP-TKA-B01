from pymongo import MongoClient
try:
    client = MongoClient("mongodb://localhost:27017", waitQueueTimeoutMS=5000)
    print("Success")
except Exception as e:
    print("Error:", e)
