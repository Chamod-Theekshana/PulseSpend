# Backend - MVC Architecture

## Structure

```
src/
├── models/              # Data models (M)
│   ├── UserModel.ts
│   └── TransactionModel.ts
├── controllers/         # Business logic (C)
│   ├── authController.ts
│   ├── signupController.ts
│   ├── transactionsController.ts
│   └── profileController.ts
├── routes/              # API routes (V)
│   ├── authRoutes.ts
│   ├── signupRoutes.ts
│   ├── transactionsRoutes.ts
│   └── profileRoutes.ts
├── middleware/          # Request processing
│   ├── rateLimiter.ts
│   ├── validators.ts
│   └── requireUser.ts
├── config/              # Configuration
│   ├── db.ts
│   ├── nodemailer.ts
│   ├── otp.ts
│   └── upstash.ts
└── server.ts            # Entry point
```

## MVC Pattern

### Model
- Database operations
- Data validation
- Located in `models/`
- Examples: UserModel, TransactionModel

### Controller
- Business logic
- Request handling
- Response formatting
- Located in `controllers/`

### View (Routes)
- API endpoints
- Request routing
- Located in `routes/`

## Data Flow

1. Client → Route → Controller → Model → Database
2. Database → Model → Controller → Route → Client
