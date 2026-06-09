# 💸 SyncCash

**Real-Time Collaborative Cashbook Platform for Business Teams**

SyncCash is a modern multi-user ledger and cashbook management platform built with Flutter and Firebase. It enables multiple business partners, store managers, and operational teams to track income, expenses, balances, and transaction history in real time through a shared cloud-synchronized ledger.

Designed specifically for small businesses, apparel stores, wholesalers, and distributed teams that require instant visibility into cash flow operations.

---

## 🚀 Features

### 🔐 Secure Authentication

* Firebase Authentication
* Email & Password Sign-In
* Session Persistence
* Password Recovery Support

### 📊 Real-Time Shared Cashbook

* Create Business Cashbooks
* Join Existing Cashbooks via Invite Codes
* Multi-User Ledger Synchronization
* Live Data Streaming

### 💰 Transaction Management

* Income Entries
* Expense Entries
* Categorized Transactions
* Transaction Descriptions & Audit Notes
* Automatic Running Balance Calculation

### 📈 Financial Dashboard

* Total Balance Tracking
* Total Income Monitoring
* Total Expense Monitoring
* Live Financial Overview

### 📜 Audit & History

* Complete Transaction History
* Chronological Transaction Logs
* User Attribution Tracking
* Timestamped Financial Events

### ☁️ Cloud Infrastructure

* Firebase Authentication
* Cloud Firestore Database
* Real-Time Data Synchronization
* Atomic Database Transactions

---

# 🏗️ System Architecture

## Frontend

* Flutter
* Riverpod State Management
* GoRouter Navigation
* Material Design UI

## Backend

* Firebase Authentication
* Cloud Firestore
* Real-Time Streams
* Transactional Database Updates

---

# 📂 Project Structure

```text
lib/
├── app/
│   ├── router/
│   ├── theme/
│   └── constants/
│
├── features/
│   ├── auth/
│   ├── cashbook/
│   ├── dashboard/
│   └── transactions/
│
├── firebase_options.dart
└── main.dart
```

---

# 🔄 Database Design

## users Collection

```json
{
  "uid": "user_id",
  "displayName": "John Doe",
  "email": "john@example.com",
  "currentCashbookId": "cashbook_id"
}
```

## cashbooks Collection

```json
{
  "inviteCode": "AB12CD",
  "ownerId": "user_id",
  "participantId": "partner_id",
  "totalBalance": 5000,
  "totalIncome": 10000,
  "totalExpense": 5000
}
```

## transactions Subcollection

```json
{
  "transactionId": "tx_id",
  "cashbookId": "cashbook_id",
  "createdBy": "user_id",
  "creatorName": "John",
  "amount": 2500,
  "type": "income",
  "category": "supplier",
  "description": "Payment received",
  "createdAt": "timestamp"
}
```

---

# ⚡ Real-Time Synchronization

Every transaction is:

1. Written to Firestore
2. Streamed to connected users
3. Applied to running balances
4. Reflected instantly across all active sessions

This allows multiple users to operate on the same business ledger simultaneously.

---

# 🛠️ Installation

## Clone Repository

```bash
git clone https://github.com/YOUR_USERNAME/SyncCash.git
cd SyncCash
```

## Install Dependencies

```bash
flutter pub get
```

## Run Application

```bash
flutter run
```

---

# 🔥 Firebase Setup

1. Create a Firebase Project
2. Enable Firebase Authentication
3. Enable Cloud Firestore
4. Add Android/Web Applications
5. Generate FlutterFire Configuration

```bash
flutterfire configure
```

---

# 🎯 Use Cases

* Retail Store Management
* Apparel Businesses
* Small Business Accounting
* Multi-Store Cash Tracking
* Shared Expense Monitoring
* Business Partner Accounting
* Operational Ledger Management

---

# 🧩 Tech Stack

| Layer            | Technology      |
| ---------------- | --------------- |
| Frontend         | Flutter         |
| State Management | Riverpod        |
| Navigation       | GoRouter        |
| Authentication   | Firebase Auth   |
| Database         | Cloud Firestore |
| Backend Services | Firebase        |
| Language         | Dart            |

---

# 📌 Future Enhancements

* PDF Invoice Generation
* Export to Excel
* Multi-Cashbook Support
* Analytics Dashboard
* Expense Approval Workflow
* Push Notifications
* Offline Sync Support
* Role-Based Access Control

---

# 👨‍💻 Author

Aniket Joshi

Software Engineering & Cybersecurity Enthusiast

Built with Flutter, Firebase, and a focus on real-time business collaboration.
