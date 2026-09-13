import React from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Users, Package, TrendingUp, Shield, Globe, ArrowRight, Building2, Star, ShoppingCart, RotateCcw, DollarSign, Bot, MapPin, Zap, Clock, BarChart3, Sparkles, CheckCircle2, AlertTriangle, Archive, FileText, Smartphone } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

const Index = () => {
  const navigate = useNavigate();

  const problems = [
    {
      icon: AlertTriangle,
      problem: "Stock-outs costing sales",
      solution: "Real-time alerts & auto-reorder points",
      color: "text-destructive"
    },
    {
      icon: FileText,
      problem: "Manual data entry errors",
      solution: "Barcode scanning & automation",
      color: "text-warning"
    },
    {
      icon: Archive,
      problem: "No visibility across locations",
      solution: "Multi-warehouse tracking",
      color: "text-primary"
    },
    {
      icon: DollarSign,
      problem: "Reconciliation nightmares",
      solution: "Automated AP/AR matching",
      color: "text-success"
    },
    {
      icon: FileText,
      problem: "GST compliance headaches",
      solution: "Built-in GST calculations",
      color: "text-accent"
    },
    {
      icon: MapPin,
      problem: "Lost tracking information",
      solution: "Track & trace module",
      color: "text-chart-2"
    }
  ];

  const features = [
    {
      icon: Package,
      title: "Real-Time Inventory Tracking",
      description: "Track stock levels across multiple warehouses with automatic low-stock alerts. Never miss a sale due to stock-outs.",
      benefit: "Save 20% on holding costs",
      gradient: "from-primary/10 to-primary/5"
    },
    {
      icon: ShoppingCart,
      title: "Smart Purchase Management",
      description: "Create GRNs, manage suppliers, track purchase orders, and auto-match invoices. Complete purchase-to-pay automation.",
      benefit: "Reduce processing time by 70%",
      gradient: "from-chart-1/10 to-chart-1/5"
    },
    {
      icon: TrendingUp,
      title: "Comprehensive Sales Module",
      description: "Generate invoices, manage customers, track orders from quotation to delivery. Complete order lifecycle management.",
      benefit: "Close deals 2x faster",
      gradient: "from-chart-2/10 to-chart-2/5"
    },
    {
      icon: RotateCcw,
      title: "Returns & Credit Notes",
      description: "Handle customer returns and supplier returns seamlessly with automated credit note generation and inventory adjustments.",
      benefit: "Streamline returns",
      gradient: "from-chart-3/10 to-chart-3/5"
    },
    {
      icon: DollarSign,
      title: "AP/AR Reconciliation Dashboard",
      description: "Automated accounts payable and receivable tracking with aging reports, payment reminders, and one-click reconciliation.",
      benefit: "Reduce payment delays by 60%",
      gradient: "from-success/10 to-success/5"
    },
    {
      icon: Bot,
      title: "AI Business Assistant",
      description: "Get intelligent insights on stock levels, demand forecasting, and business recommendations powered by Gemini AI.",
      benefit: "AI-powered decisions",
      gradient: "from-accent/10 to-accent/5"
    },
    {
      icon: MapPin,
      title: "Track & Trace Module",
      description: "Real-time order tracking, location-based updates, and automatic customer notifications for complete transparency.",
      benefit: "Improve customer satisfaction",
      gradient: "from-warning/10 to-warning/5"
    },
    {
      icon: Building2,
      title: "Multi-Business & Role Management",
      description: "Manage multiple businesses with separate data isolation. Assign roles and permissions for complete team control.",
      benefit: "Enterprise-grade security",
      gradient: "from-muted/10 to-muted/5"
    }
  ];

  const testimonials = [
    {
      quote: "Reduced inventory errors by 95% within the first month",
      author: "Rajesh Kumar",
      company: "Mumbai Manufacturing Co.",
      metric: "95% error reduction"
    },
    {
      quote: "Saved 15 hours weekly on manual data entry and reconciliation",
      author: "Priya Sharma",
      company: "Delhi Retail Chain",
      metric: "15 hrs saved/week"
    },
    {
      quote: "Improved cash flow with AP/AR automation. Game changer!",
      author: "Amit Patel",
      company: "Ahmedabad Trading Firm",
      metric: "30% faster payments"
    }
  ];

  const techStack = [
    { name: "React", icon: Zap, description: "Lightning fast" },
    { name: "TypeScript", icon: Shield, description: "Type-safe" },
    { name: "Supabase", icon: Globe, description: "Secure cloud" },
    { name: "PWA", icon: Smartphone, description: "Offline-capable" }
  ];

  const pricingPlans = [
    {
      name: "Free Trial",
      price: "₹0",
      period: "30 days",
      description: "Try all features risk-free",
      features: [
        "All Premium features included",
        "Unlimited products & SKUs",
        "Multi-warehouse management",
        "Purchase & sales modules",
        "AI-powered insights",
        "Email & WhatsApp support",
        "No credit card required"
      ],
      popular: false,
      planType: "trial",
      isTrial: true
    },
    {
      name: "Monthly",
      price: "₹999",
      period: "/month",
      description: "Perfect for growing businesses",
      features: [
        "Unlimited products & SKUs",
        "Multi-warehouse management",
        "Purchase & sales modules",
        "Returns & credit notes",
        "AP/AR reconciliation",
        "AI business assistant",
        "Barcode scanning",
        "Track & trace",
        "Role-based access control",
        "GST compliance",
        "Cloud backup & security",
        "Email & WhatsApp support"
      ],
      popular: false,
      planType: "monthly"
    },
    {
      name: "Yearly",
      price: "₹10,000",
      period: "/year",
      description: "Best value - Save ₹1,988 annually",
      features: [
        "Everything in Monthly plan",
        "Priority 24/7 support",
        "Advanced analytics & custom reports",
        "API access for integrations",
        "Dedicated account manager",
        "Free onboarding & training",
        "Data migration assistance",
        "Custom workflows",
        "White-label options"
      ],
      popular: true,
      planType: "yearly",
      savings: "Save ₹1,988"
    }
  ];

  const handleSubscribe = (planType: string) => {
    if (planType === 'trial') {
      navigate('/register?plan=trial');
    } else {
      navigate(`/subscribe/${planType}`);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-subtle">
      {/* Header */}
      <header className="border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60 sticky top-0 z-50">
        <div className="content-container section-padding">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-2">
              <div className="relative">
                <Star className="h-8 w-8 text-primary fill-primary" />
                <Sparkles className="h-4 w-4 text-primary absolute -top-1 -right-1" />
              </div>
              <div>
                <span className="text-2xl font-bold bg-gradient-to-r from-primary to-chart-2 bg-clip-text text-transparent">
                  Rigel Inventory
                </span>
                <p className="text-xs text-muted-foreground">Navigate Your Business to Success</p>
              </div>
            </div>
            <Button 
              onClick={() => {
                console.log('Sign In button clicked');
                // Navigate directly, let EnhancedAuth handle any stale state
                navigate('/auth');
              }} 
              variant="outline" 
              className="hover-scale"
            >
              Sign In
            </Button>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="relative overflow-hidden bg-gradient-to-br from-background via-primary/5 to-chart-2/5 py-20 lg:py-32">
        <div className="absolute inset-0 bg-grid-pattern opacity-5"></div>
        <div className="content-container relative">
          <div className="grid lg:grid-cols-2 gap-12 items-center">
            {/* Left Content */}
            <div className="space-y-8 animate-fade-up">
              <Badge variant="secondary" className="mb-4 px-4 py-2">
                <CheckCircle2 className="w-4 h-4 mr-2" />
                GST Compliant | Multi-location | AI-Powered
              </Badge>
              <h1 className="text-4xl md:text-6xl lg:text-7xl font-bold text-foreground leading-tight">
                Stop Losing Money on{" "}
                <span className="bg-gradient-to-r from-primary via-chart-2 to-accent bg-clip-text text-transparent">
                  Inventory Mistakes
                </span>
              </h1>
              <p className="text-xl md:text-2xl text-muted-foreground leading-relaxed">
                Rigel Inventory helps Indian businesses track stock, manage purchases, and boost profits with intelligent automation. 
                <span className="font-semibold text-foreground"> Join 1000+ businesses saving ₹50,000+ monthly.</span>
              </p>
              
              {/* Trust Indicators */}
              <div className="flex flex-wrap gap-6 pt-4">
                <div className="flex items-center gap-2">
                  <div className="w-10 h-10 rounded-full bg-success/10 flex items-center justify-center">
                    <CheckCircle2 className="w-5 h-5 text-success" />
                  </div>
                  <div>
                    <p className="font-semibold text-foreground">1000+</p>
                    <p className="text-sm text-muted-foreground">Active Users</p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-10 h-10 rounded-full bg-chart-2/10 flex items-center justify-center">
                    <TrendingUp className="w-5 h-5 text-chart-2" />
                  </div>
                  <div>
                    <p className="font-semibold text-foreground">10M+</p>
                    <p className="text-sm text-muted-foreground">Transactions</p>
                  </div>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                    <Star className="w-5 h-5 text-primary fill-primary" />
                  </div>
                  <div>
                    <p className="font-semibold text-foreground">4.8/5</p>
                    <p className="text-sm text-muted-foreground">Rating</p>
                  </div>
                </div>
              </div>

              <div className="flex flex-col sm:flex-row gap-4 pt-4">
                <Button 
                  size="lg" 
                  className="btn-gradient text-lg px-8 h-14 hover-scale w-full sm:w-auto"
                  onClick={() => navigate('/register?plan=trial')}
                >
                  Start Free 30-Day Trial <ArrowRight className="ml-2 h-5 w-5" />
                </Button>
              </div>

              <p className="text-sm text-muted-foreground pt-2">
                ✓ No credit card required  ✓ Setup in 5 minutes  ✓ Cancel anytime
              </p>
            </div>

            {/* Right Visual */}
            <div className="relative animate-scale-in">
              <div className="relative rounded-2xl border-2 border-primary/20 bg-card shadow-2xl overflow-hidden">
                <div className="bg-gradient-to-br from-primary/10 to-chart-2/10 p-8">
                  <div className="space-y-4">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <Star className="w-6 h-6 text-primary fill-primary" />
                        <span className="font-bold text-xl">Rigel Dashboard</span>
                      </div>
                      <Badge variant="secondary">Live</Badge>
                    </div>
                    
                    <div className="grid grid-cols-2 gap-4">
                      <Card className="p-4">
                        <div className="flex items-center gap-3">
                          <Package className="w-8 h-8 text-primary" />
                          <div>
                            <p className="text-2xl font-bold">2,547</p>
                            <p className="text-xs text-muted-foreground">Total Products</p>
                          </div>
                        </div>
                      </Card>
                      <Card className="p-4">
                        <div className="flex items-center gap-3">
                          <TrendingUp className="w-8 h-8 text-success" />
                          <div>
                            <p className="text-2xl font-bold">₹12.5L</p>
                            <p className="text-xs text-muted-foreground">Monthly Sales</p>
                          </div>
                        </div>
                      </Card>
                      <Card className="p-4">
                        <div className="flex items-center gap-3">
                          <AlertTriangle className="w-8 h-8 text-warning" />
                          <div>
                            <p className="text-2xl font-bold">12</p>
                            <p className="text-xs text-muted-foreground">Low Stock</p>
                          </div>
                        </div>
                      </Card>
                      <Card className="p-4">
                        <div className="flex items-center gap-3">
                          <Bot className="w-8 h-8 text-accent" />
                          <div>
                            <p className="text-2xl font-bold">AI</p>
                            <p className="text-xs text-muted-foreground">Insights Ready</p>
                          </div>
                        </div>
                      </Card>
                    </div>
                  </div>
                </div>
              </div>
              
              {/* Floating Elements */}
              <div className="absolute -top-6 -right-6 w-32 h-32 bg-primary/20 rounded-full blur-3xl animate-pulse"></div>
              <div className="absolute -bottom-6 -left-6 w-32 h-32 bg-chart-2/20 rounded-full blur-3xl animate-pulse" style={{ animationDelay: '1s' }}></div>
            </div>
          </div>
        </div>
      </section>

      {/* Problems We Solve Section */}
      <section className="section-padding py-20 bg-muted/30">
        <div className="content-container">
          <div className="text-center space-y-4 mb-16">
            <Badge variant="outline" className="mb-2">
              <Sparkles className="w-3 h-3 mr-2" />
              Problems We Solve
            </Badge>
            <h2 className="text-3xl md:text-5xl font-bold text-foreground">
              Turn Your Inventory Chaos into <span className="text-primary">Clarity</span>
            </h2>
            <p className="text-xl text-muted-foreground max-w-3xl mx-auto">
              Say goodbye to these common inventory nightmares
            </p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-6 stagger-animation">
            {problems.map((item, index) => (
              <Card key={index} className="card-interactive border-l-4" style={{ borderLeftColor: 'hsl(var(--primary))' }}>
                <CardHeader>
                  <div className="flex items-start gap-4">
                    <div className={`w-12 h-12 rounded-lg bg-destructive/10 flex items-center justify-center flex-shrink-0`}>
                      <item.icon className={`h-6 w-6 ${item.color}`} />
                    </div>
                    <div className="space-y-2 flex-1">
                      <p className="font-semibold text-base text-muted-foreground line-through">{item.problem}</p>
                      <div className="flex items-start gap-2">
                        <CheckCircle2 className="w-5 h-5 text-success flex-shrink-0 mt-0.5" />
                        <p className="font-bold text-foreground">{item.solution}</p>
                      </div>
                    </div>
                  </div>
                </CardHeader>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="section-padding py-20">
        <div className="content-container">
          <div className="text-center space-y-4 mb-16">
            <Badge variant="outline" className="mb-2">
              <Zap className="w-3 h-3 mr-2" />
              Powerful Features
            </Badge>
            <h2 className="text-3xl md:text-5xl font-bold text-foreground">
              Everything You Need to <span className="text-primary">Scale</span>
            </h2>
            <p className="text-xl text-muted-foreground max-w-3xl mx-auto">
              End-to-end inventory management suite built for modern Indian businesses
            </p>
          </div>
          
          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6 stagger-animation">
            {features.map((feature, index) => (
              <Card key={index} className="card-interactive border-0 shadow-card hover:shadow-elevated transition-all group">
                <CardHeader className="pb-4">
                  <div className={`w-14 h-14 rounded-xl bg-gradient-to-br ${feature.gradient} flex items-center justify-center mb-4 group-hover:scale-110 transition-transform`}>
                    <feature.icon className="h-7 w-7 text-primary" />
                  </div>
                  <CardTitle className="text-lg group-hover:text-primary transition-colors">{feature.title}</CardTitle>
                </CardHeader>
                <CardContent className="space-y-3">
                  <CardDescription className="text-sm leading-relaxed">
                    {feature.description}
                  </CardDescription>
                  <Badge variant="secondary" className="text-xs font-medium">
                    <TrendingUp className="w-3 h-3 mr-1" />
                    {feature.benefit}
                  </Badge>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </section>

      {/* Demo Section */}
      <section id="demo" className="section-padding py-12 md:py-20 bg-gradient-to-br from-primary/5 to-chart-2/5">
        <div className="content-container">
          <div className="max-w-4xl mx-auto">
            <div className="text-center space-y-4 md:space-y-6 mb-8 md:mb-12">
              <Badge variant="outline">
                <BarChart3 className="w-3 h-3 mr-2" />
                See It In Action
              </Badge>
              <h2 className="text-2xl md:text-5xl font-bold text-foreground px-4">
                Watch Rigel Inventory in Action
              </h2>
              <p className="text-base md:text-xl text-muted-foreground px-4">
                See how businesses transform their operations in just 5 minutes
              </p>
            </div>
            
            <Card className="overflow-hidden shadow-2xl">
              <div className="aspect-video bg-gradient-to-br from-muted to-muted/50 flex items-center justify-center relative group cursor-pointer hover:scale-[1.02] transition-transform">
                <div className="absolute inset-0 bg-gradient-to-br from-primary/20 to-chart-2/20"></div>
                <div className="relative z-10 text-center space-y-3 md:space-y-4 px-4">
                  <div className="w-16 h-16 md:w-20 md:h-20 mx-auto rounded-full bg-primary/20 backdrop-blur-sm flex items-center justify-center group-hover:scale-110 transition-transform">
                    <div className="w-14 h-14 md:w-16 md:h-16 rounded-full bg-primary flex items-center justify-center">
                      <BarChart3 className="w-6 h-6 md:w-8 md:h-8 text-primary-foreground" />
                    </div>
                  </div>
                  <div>
                    <p className="font-bold text-lg md:text-2xl text-foreground">Interactive Product Demo</p>
                    <p className="text-sm md:text-base text-muted-foreground">Click to explore features</p>
                  </div>
                </div>
              </div>
              <CardFooter className="flex-col sm:flex-row justify-center gap-3 md:gap-4 py-4 md:py-6 bg-card">
                <Button size="lg" className="btn-gradient w-full sm:w-auto text-sm md:text-base" onClick={() => navigate('/register?plan=trial')}>
                  <Sparkles className="mr-2 h-4 w-4 md:h-5 md:w-5" />
                  Try Free for 30 Days
                </Button>
                <Button size="lg" variant="outline" className="w-full sm:w-auto text-sm md:text-base">
                  <Globe className="mr-2 h-4 w-4 md:h-5 md:w-5" />
                  Book Live Demo
                </Button>
              </CardFooter>
            </Card>
          </div>
        </div>
      </section>

      {/* Social Proof Section */}
      <section className="section-padding py-20">
        <div className="content-container">
          <div className="text-center space-y-4 mb-16">
            <Badge variant="outline">
              <Star className="w-3 h-3 mr-2 fill-primary text-primary" />
              Customer Success Stories
            </Badge>
            <h2 className="text-3xl md:text-5xl font-bold text-foreground">
              Trusted by <span className="text-primary">Growing Businesses</span>
            </h2>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8 mb-16">
            {testimonials.map((testimonial, index) => (
              <Card key={index} className="card-interactive">
                <CardHeader>
                  <div className="flex gap-1 mb-4">
                    {[...Array(5)].map((_, i) => (
                      <Star key={i} className="w-5 h-5 fill-primary text-primary" />
                    ))}
                  </div>
                  <CardDescription className="text-base leading-relaxed text-foreground italic">
                    "{testimonial.quote}"
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <div className="space-y-1">
                    <p className="font-semibold text-foreground">{testimonial.author}</p>
                    <p className="text-sm text-muted-foreground">{testimonial.company}</p>
                    <Badge variant="secondary" className="mt-2">
                      <TrendingUp className="w-3 h-3 mr-1" />
                      {testimonial.metric}
                    </Badge>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>

          {/* Trust Metrics */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 max-w-4xl mx-auto">
            <div className="text-center">
              <p className="text-4xl font-bold text-primary mb-2">1000+</p>
              <p className="text-muted-foreground">Businesses Trust Us</p>
            </div>
            <div className="text-center">
              <p className="text-4xl font-bold text-primary mb-2">10M+</p>
              <p className="text-muted-foreground">Transactions</p>
            </div>
            <div className="text-center">
              <p className="text-4xl font-bold text-primary mb-2">99.9%</p>
              <p className="text-muted-foreground">Uptime</p>
            </div>
            <div className="text-center">
              <p className="text-4xl font-bold text-primary mb-2">4.8/5</p>
              <p className="text-muted-foreground">Rating</p>
            </div>
          </div>
        </div>
      </section>

      {/* Pricing Section */}
      <section id="pricing" className="section-padding py-20 bg-muted/30">
        <div className="content-container">
          <div className="text-center space-y-4 mb-16">
            <Badge variant="outline">
              <DollarSign className="w-3 h-3 mr-2" />
              Transparent Pricing
            </Badge>
            <h2 className="text-3xl md:text-5xl font-bold text-foreground">
              Start Free, Scale as You <span className="text-primary">Grow</span>
            </h2>
            <p className="text-xl text-muted-foreground max-w-3xl mx-auto">
              No hidden fees. No surprises. Just powerful inventory management at prices that work for Indian businesses.
            </p>
          </div>
          
          <div className="grid md:grid-cols-3 gap-8 max-w-6xl mx-auto mb-12">
            {pricingPlans.map((plan, index) => (
              <Card 
                key={index} 
                className={`card-interactive relative hover-scale ${
                  plan.popular 
                    ? 'border-primary shadow-elevated ring-2 ring-primary/20 scale-105' 
                    : 'border-border shadow-card'
                }`}
              >
                {plan.popular && (
                  <div className="absolute -top-3 left-1/2 transform -translate-x-1/2 z-10">
                    <Badge className="bg-gradient-to-r from-primary to-chart-2 text-primary-foreground px-4 py-1.5">
                      <Star className="w-3 h-3 mr-1 fill-current" />
                      Most Popular
                    </Badge>
                  </div>
                )}
                {plan.savings && (
                  <div className="absolute -top-3 right-4">
                    <Badge variant="secondary" className="bg-success text-success-foreground">
                      {plan.savings}
                    </Badge>
                  </div>
                )}
                <CardHeader className="text-center pb-8 pt-8">
                  <CardTitle className="text-2xl font-bold">{plan.name}</CardTitle>
                  <div className="mt-6">
                    <span className="text-5xl font-bold text-foreground">{plan.price}</span>
                    <span className="text-muted-foreground text-lg">/{plan.period}</span>
                  </div>
                  <CardDescription className="text-base mt-3 font-medium">
                    {plan.description}
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-3 pb-8">
                  {plan.features.map((feature, featureIndex) => (
                    <div key={featureIndex} className="flex items-start space-x-3">
                      <CheckCircle2 className="h-5 w-5 text-success flex-shrink-0 mt-0.5" />
                      <span className="text-sm leading-relaxed">{feature}</span>
                    </div>
                  ))}
                </CardContent>
                <CardFooter className="pt-0">
                  <Button 
                    className={`w-full text-lg h-12 hover-scale ${
                      plan.popular ? 'btn-gradient shadow-lg' : ''
                    }`}
                    variant={plan.popular ? "default" : "outline"}
                    size="lg"
                    onClick={() => handleSubscribe(plan.planType)}
                  >
                    {plan.isTrial ? (
                      <>
                        <Sparkles className="mr-2 h-5 w-5" />
                        Start Free Trial
                      </>
                    ) : (
                      <>
                        Get Started
                        <ArrowRight className="ml-2 h-5 w-5" />
                      </>
                    )}
                  </Button>
                </CardFooter>
              </Card>
            ))}
          </div>

          {/* Trust Footer */}
          <div className="text-center space-y-4 pt-8">
            <p className="text-muted-foreground">
              ✓ No credit card required for trial  ✓ Full feature access  ✓ Setup in 5 minutes  ✓ Cancel anytime
            </p>
            <div className="flex items-center justify-center gap-2 flex-wrap">
              <Badge variant="outline" className="px-4 py-2">
                <Shield className="w-4 h-4 mr-2" />
                Bank-grade encryption
              </Badge>
              <Badge variant="outline" className="px-4 py-2">
                <Clock className="w-4 h-4 mr-2" />
                99.9% uptime SLA
              </Badge>
              <Badge variant="outline" className="px-4 py-2">
                <CheckCircle2 className="w-4 h-4 mr-2" />
                GST compliant
              </Badge>
            </div>
          </div>
        </div>
      </section>

      {/* Technology Section */}
      <section className="section-padding py-20">
        <div className="content-container">
          <div className="text-center space-y-4 mb-16">
            <Badge variant="outline">
              <Zap className="w-3 h-3 mr-2" />
              Built with Modern Technology
            </Badge>
            <h2 className="text-3xl md:text-5xl font-bold text-foreground">
              Fast, Secure, <span className="text-primary">Future-Ready</span>
            </h2>
          </div>
          
          <div className="grid grid-cols-2 md:grid-cols-4 gap-6 max-w-4xl mx-auto">
            {techStack.map((tech, index) => (
              <Card key={index} className="card-interactive text-center p-6 hover-scale">
                <div className="w-16 h-16 mx-auto rounded-xl bg-gradient-to-br from-primary/10 to-chart-2/10 flex items-center justify-center mb-4">
                  <tech.icon className="w-8 h-8 text-primary" />
                </div>
                <h3 className="font-bold text-lg mb-1">{tech.name}</h3>
                <p className="text-sm text-muted-foreground">{tech.description}</p>
              </Card>
            ))}
          </div>

          <div className="mt-12 text-center">
            <p className="text-muted-foreground mb-4">
              Real-time sync • Offline-capable PWA • Bank-grade encryption • ISO 27001 ready
            </p>
          </div>
        </div>
      </section>

      {/* Final CTA Section */}
      <section className="section-padding py-20 bg-gradient-to-br from-primary/10 via-chart-2/10 to-accent/10">
        <div className="content-container">
          <div className="max-w-4xl mx-auto text-center space-y-8">
            <Badge variant="secondary" className="px-4 py-2">
              <Sparkles className="w-4 h-4 mr-2" />
              Join 1000+ successful businesses
            </Badge>
            <h2 className="text-4xl md:text-6xl font-bold text-foreground">
              Ready to Transform Your Inventory Management?
            </h2>
            <p className="text-xl text-muted-foreground max-w-2xl mx-auto">
              Start your free 30-day trial today. No credit card required. Full feature access. Cancel anytime.
            </p>
            
            <div className="flex flex-col sm:flex-row gap-4 justify-center pt-4">
              <Button 
                size="lg" 
                className="btn-gradient text-xl px-10 h-16 hover-scale shadow-xl"
                onClick={() => handleSubscribe('trial')}
              >
                <Sparkles className="mr-2 h-6 w-6" />
                Start Free 30-Day Trial
              </Button>
              <Button 
                size="lg" 
                variant="outline" 
                className="text-xl px-10 h-16 hover-scale"
              >
                <Globe className="mr-2 h-6 w-6" />
                Book a Demo Call
              </Button>
            </div>

            <div className="pt-6 space-y-2">
              <p className="text-sm text-muted-foreground">
                ✓ No credit card required  ✓ Full feature access  ✓ Dedicated onboarding support  ✓ Cancel anytime
              </p>
              <p className="text-sm font-semibold text-foreground">
                Questions? Email us at support@rigelinventory.com or call +91-XXXX-XXXXXX
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t bg-card">
        <div className="content-container section-padding py-12">
          <div className="grid md:grid-cols-4 gap-8 mb-8">
            {/* Brand */}
            <div className="space-y-4">
              <div className="flex items-center space-x-2">
                <div className="relative">
                  <Star className="h-8 w-8 text-primary fill-primary" />
                  <Sparkles className="h-4 w-4 text-primary absolute -top-1 -right-1" />
                </div>
                <div>
                  <span className="text-xl font-bold bg-gradient-to-r from-primary to-chart-2 bg-clip-text text-transparent">
                    Rigel Inventory
                  </span>
                </div>
              </div>
              <p className="text-sm text-muted-foreground">
                Navigate your business to success with intelligent inventory management.
              </p>
              <div className="flex gap-4">
                <Button variant="ghost" size="icon">
                  <Globe className="h-5 w-5" />
                </Button>
                <Button variant="ghost" size="icon">
                  <Users className="h-5 w-5" />
                </Button>
              </div>
            </div>

            {/* Product */}
            <div>
              <h3 className="font-semibold mb-4">Product</h3>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li><a href="#" className="hover:text-primary transition-colors">Features</a></li>
                <li><a href="#pricing" className="hover:text-primary transition-colors">Pricing</a></li>
                <li><a href="#" className="hover:text-primary transition-colors">Updates</a></li>
                <li><a href="#" className="hover:text-primary transition-colors">Roadmap</a></li>
              </ul>
            </div>

            {/* Resources */}
            <div>
              <h3 className="font-semibold mb-4">Resources</h3>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li><a href="#" className="hover:text-primary transition-colors">Help Center</a></li>
                <li><a href="#demo" className="hover:text-primary transition-colors">Demo</a></li>
                <li><a href="#" className="hover:text-primary transition-colors">API Docs</a></li>
                <li><a href="#" className="hover:text-primary transition-colors">Blog</a></li>
              </ul>
            </div>

            {/* Company */}
            <div>
              <h3 className="font-semibold mb-4">Company</h3>
              <ul className="space-y-2 text-sm text-muted-foreground">
                <li><a href="#" className="hover:text-primary transition-colors">About Us</a></li>
                <li><a href="#" className="hover:text-primary transition-colors">Contact</a></li>
                <li><a href="#" className="hover:text-primary transition-colors">Privacy Policy</a></li>
                <li><a href="#" className="hover:text-primary transition-colors">Terms of Service</a></li>
              </ul>
            </div>
          </div>

          <div className="border-t pt-8 text-center">
            <p className="text-sm text-muted-foreground">
              © 2024 Rigel Inventory by Rigel Tech Solutions. All rights reserved.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
};

export default Index;